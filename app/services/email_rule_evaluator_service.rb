# frozen_string_literal: true

# Evaluates email rules: finds shops or uninstalled_shops matching date rule + conditions (with AND/OR), excluding those already sent.
# Rule target determines which pool is scanned: "shops" or "uninstalled_shops".
# Conditions are applied in the database via dynamically built WHERE clauses (no in-memory iteration).
module EmailRuleEvaluatorService
  module_function

  def candidate_shop_ids_for_rule(rule)
    return [] if rule_target(rule) != "shops"
    scope = Shop.includes(:setting)
                .where.not(id: ScheduledEmail.where(email_rule_id: rule.id).where.not(shop_id: nil).select(:shop_id))
    scope = apply_date_rule_shop(scope, rule)
    scope = apply_conditions_scope_shop(scope, rule)
    scope.pluck(:id)
  end

  def candidate_uninstalled_shop_ids_for_rule(rule)
    return [] if rule_target(rule) != "uninstalled_shops"
    scope = UninstalledShop.where.not(
      id: ScheduledEmail.where(email_rule_id: rule.id).where.not(uninstalled_shop_id: nil).select(:uninstalled_shop_id)
    )
    scope = apply_date_rule_uninstalled(scope, rule)
    scope = apply_conditions_scope_uninstalled(scope, rule)
    scope.pluck(:id)
  end

  def rule_satisfied_for_shop?(rule, shop)
    return false unless rule_target(rule) == "shops"
    return false unless date_rule_satisfied?(rule, shop, :shop)
    conditions_satisfied?(rule, shop, :shop)
  end

  def rule_satisfied_for_uninstalled_shop?(rule, uninstalled_shop)
    return false unless rule_target(rule) == "uninstalled_shops"
    return false unless date_rule_satisfied?(rule, uninstalled_shop, :uninstalled_shop)
    conditions_satisfied?(rule, uninstalled_shop, :uninstalled_shop)
  end

  def rule_target(rule)
    rule.respond_to?(:target) && rule.target.present? ? rule.target.to_s : "shops"
  end

  # Debug: run in console to see where candidate_shop_ids drops to zero.
  # EmailRuleEvaluatorService.debug_candidate_scope(EmailRule.find(1))
  def debug_candidate_scope(rule)
    return { error: "rule target is not shops" } if rule_target(rule) != "shops"

    base = Shop.where.not(
      id: ScheduledEmail.where(email_rule_id: rule.id).where.not(shop_id: nil).select(:shop_id)
    )
    after_date = apply_date_rule_shop(base, rule)
    after_conditions = apply_conditions_scope_shop(after_date, rule)

    {
      conditions_array: rule.conditions_array,
      conditions_array_empty: rule.conditions_array.empty?,
      date_rule_column: rule.respond_to?(:date_rule_column) ? rule.date_rule_column : nil,
      date_rule_value: rule.respond_to?(:date_rule_value) ? rule.date_rule_value : nil,
      threshold: date_rule_threshold(rule),
      count_after_exclusion: base.count,
      count_after_date_rule: after_date.count,
      count_after_conditions: after_conditions.count,
      final_sql: after_conditions.to_sql
    }
  end

  def apply_date_rule_shop(scope, rule)
    table, column = date_rule_table_column(rule)
    threshold = date_rule_threshold(rule)
    if table == "shops"
      scope.where("shops.#{column} IS NOT NULL AND shops.#{column} <= ?", threshold)
    elsif table == "settings"
      scope = scope.joins(:setting)
      scope.where("settings.#{column} IS NOT NULL AND settings.#{column} <= ?", threshold)
    else
      scope.none
    end
  end

  def apply_date_rule_uninstalled(scope, rule)
    table, column = date_rule_table_column(rule)
    return scope.none unless table == "uninstalled_shops"
    return scope.none unless scope.klass.column_names.include?(column)
    threshold = date_rule_threshold(rule)
    scope.where("#{scope.klass.table_name}.#{column} IS NOT NULL AND #{scope.klass.table_name}.#{column} <= ?", threshold)
  end

  def date_rule_threshold(rule)
    if rule.respond_to?(:date_rule_type) && rule.date_rule_type == "hours_after_installation"
      rule.date_rule_value.to_i.hours.ago
    else
      rule.date_rule_value.to_i.days.ago
    end
  end

  def apply_date_rule(scope, rule)
    apply_date_rule_shop(scope, rule)
  end

  # Apply conditions as database WHERE (no in-memory iteration). Returns scope.
  def apply_conditions_scope_shop(scope, rule)
    arr = rule.conditions_array
    return scope if arr.empty?

    date_table, _ = date_rule_table_column(rule)
    need_settings_join = arr.any? { |c| cond_val(c, "table").to_s == "settings" } && date_table != "settings"
    scope = scope.left_joins(:setting) if need_settings_join

    parts = []
    arr.each_with_index do |c, i|
      sql, part_binds = condition_sql_shop(c)
      next if sql.blank? || sql == "1=0"
      combiner = i == 0 ? nil : (cond_val(arr[i - 1], "combiner") || "and").to_s.upcase
      parts << [sql, part_binds, combiner]
    end
    return scope if parts.empty?

    combined = parts.map.with_index { |(sql, _, combiner), j| j == 0 ? "(#{sql})" : "#{combiner} (#{sql})" }.join(" ")
    binds = parts.flat_map { |_, b, _| b }
    scope.where(combined, *binds)
  end

  def apply_conditions_scope_uninstalled(scope, rule)
    arr = rule.conditions_array
    return scope if arr.empty?

    table_name = "uninstalled_shops"
    parts = []
    arr.each_with_index do |c, i|
      sql, part_binds = condition_sql_uninstalled(c, table_name)
      next if sql.blank? || sql == "1=0"
      combiner = i == 0 ? nil : (cond_val(arr[i - 1], "combiner") || "and").to_s.upcase
      parts << [sql, part_binds, combiner]
    end
    return scope if parts.empty?

    combined = parts.map.with_index { |(sql, _, combiner), j| j == 0 ? "(#{sql})" : "#{combiner} (#{sql})" }.join(" ")
    binds = parts.flat_map { |_, b, _| b }
    scope.where(combined, *binds)
  end

  # Condition hash may have string or symbol keys (e.g. from JSON).
  def cond_val(c, key)
    return nil unless c.is_a?(Hash)
    c[key] || c[key.to_sym]
  end

  # Returns [sql_fragment, array_of_bind_values] for one condition on shops/settings. Safe column names only.
  def condition_sql_shop(c)
    table = cond_val(c, "table").to_s
    column = cond_val(c, "column").to_s
    op = cond_val(c, "op").to_s
    value = cond_val(c, "value")

    if table == "shops"
      return ["1=0", []] unless Shop.column_names.include?(column)
      build_condition_sql("shops", column, op, value)
    elsif table == "settings"
      return ["1=0", []] unless Setting.column_names.include?(column)
      build_condition_sql_settings(column, op, value)
    else
      ["1=0", []]
    end
  end

  def condition_sql_uninstalled(c, table_name)
    table = cond_val(c, "table").to_s
    column = cond_val(c, "column").to_s
    return ["1=0", []] unless table == "uninstalled_shops"
    return ["1=0", []] unless UninstalledShop.column_names.include?(column)
    build_condition_sql(table_name, column, cond_val(c, "op").to_s, cond_val(c, "value"))
  end

  def build_condition_sql(table_name, column, op, value)
    quoted = "#{table_name}.#{column}"
    case op
    when "eq"
      bind_value = coerce_bind_value(value)
      bind_value = false if value.is_a?(String) && value.downcase == "false"
      bind_value = true  if value.is_a?(String) && value.downcase == "true"
      ["#{quoted} = ?", [bind_value]]
    when "not_eq"
      bind_value = coerce_bind_value(value)
      bind_value = false if value.is_a?(String) && value.downcase == "false"
      bind_value = true  if value.is_a?(String) && value.downcase == "true"
      ["#{quoted} != ? OR #{quoted} IS NULL", [bind_value]]
    when "gt"
      ["#{quoted} > ?", [coerce_bind_value(value)]]
    when "gteq"
      ["#{quoted} >= ?", [coerce_bind_value(value)]]
    when "lt"
      ["#{quoted} < ?", [coerce_bind_value(value)]]
    when "lteq"
      ["#{quoted} <= ?", [coerce_bind_value(value)]]
    when "true"
      ["#{quoted} = ?", [true]]
    when "false"
      ["#{quoted} IS NOT TRUE", []]
    when "present"
      ["(#{quoted} IS NOT NULL AND #{quoted}::text <> '')", []]
    when "blank"
      # Match nil, empty string, whitespace-only, and boolean false (Rails blank?)
      ["(#{quoted} IS NULL OR #{quoted}::text = '' OR trim(#{quoted}::text) = '' OR #{quoted}::text = 'f')", []]
    else
      ["1=1", []]
    end
  end

  def build_condition_sql_settings(column, op, value)
    quoted = "settings.#{column}"
    # When shop has no setting: only "blank" and "false" pass in the in-memory logic.
    case op
    when "blank"
      ["(settings.id IS NULL OR #{quoted} IS NULL OR #{quoted}::text = '')", []]
    when "false"
      ["(settings.id IS NULL OR #{quoted} IS NOT TRUE)", []]
    else
      sql, binds = build_condition_sql("settings", column, op, value)
      # Shop must have a setting for other ops
      ["(settings.id IS NOT NULL AND #{sql})", binds]
    end
  end

  def coerce_bind_value(value)
    return nil if value.nil?
    return true if value.is_a?(String) && value.strip.downcase.in?(["true", "yes", "1"])
    return false if value.is_a?(String) && value.strip.downcase.in?(["false", "no", "0"])
    return value.to_i if value.is_a?(String) && value.strip.match?(/\A-?\d+\z/)
    return value.to_f if value.is_a?(String) && value.strip.match?(/\A-?\d+(\.\d+)?\z/)
    value
  end

  def date_rule_satisfied?(rule, record, target_type)
    table, column = date_rule_table_column(rule)
    threshold = date_rule_threshold(rule)
    if target_type == :uninstalled_shop
      return false unless table == "uninstalled_shops"
      return false unless record.respond_to?(column)
      date_val = record.public_send(column)
      return false if date_val.blank?
      return date_val <= threshold
    end
    rec = table == "settings" ? record.setting : record
    return false if rec.nil?
    return false unless rec.respond_to?(column)
    date_val = rec.public_send(column)
    return false if date_val.blank?
    date_val <= threshold
  end

  def date_rule_table_column(rule)
    if rule.respond_to?(:date_rule_column) && rule.date_rule_column.present?
      parts = rule.date_rule_column.split(".", 2)
      [parts[0], parts[1]]
    else
      # Legacy: days_after_installation
      ["shops", "created_at"]
    end
  end

  # Combine conditions with AND/OR. record is Shop or UninstalledShop; target_type is :shop or :uninstalled_shop.
  def conditions_satisfied?(rule, record, target_type)
    arr = rule.conditions_array
    return true if arr.empty?
    result = condition_satisfied?(arr[0], record, target_type)
    arr.each_with_index do |c, i|
      next if i == 0
      combiner = (arr[i - 1]["combiner"] || "and").to_s.downcase
      current = condition_satisfied?(c, record, target_type)
      result = combiner == "or" ? (result || current) : (result && current)
    end
    result
  end

  def condition_satisfied?(c, record, target_type)
    table = c["table"].to_s
    column = c["column"].to_s
    op = c["op"].to_s
    value = c["value"]
    val = value.is_a?(String) && value.in?(["true", "false"]) ? (value == "true") : value

    if target_type == :uninstalled_shop
      return false unless table == "uninstalled_shops"
      return false unless record.respond_to?(column)
      actual = record.public_send(column)
    else
      rec = table == "settings" ? record.setting : record
      if table == "settings" && rec.nil?
        return true if %w[blank false].include?(op)
        return false
      end
      return false if rec.nil?
      return false unless rec.respond_to?(column)
      actual = rec.public_send(column)
    end

    # Coerce form value for comparison: "33" (string) should match 33 (integer)
    comparable_val = coerce_condition_value(actual, val)

    case op
    when "eq"
      actual == comparable_val || (comparable_val == false && actual != true)
    when "not_eq"
      actual != comparable_val
    when "gt"
      compare(actual, comparable_val) { |a, b| a > b }
    when "gteq"
      compare(actual, comparable_val) { |a, b| a >= b }
    when "lt"
      compare(actual, comparable_val) { |a, b| a < b }
    when "lteq"
      compare(actual, comparable_val) { |a, b| a <= b }
    when "true"
      actual == true
    when "false"
      actual != true
    when "present"
      actual.present?
    when "blank"
      actual.blank?
    else
      true
    end
  end

  def coerce_condition_value(actual, value)
    return value if value.nil?
    return value if value.is_a?(String) && value.in?(["true", "false"]) # already handled as boolean
    if actual.is_a?(Integer) && value.to_s.match?(/\A-?\d+\z/)
      value.to_i
    elsif actual.is_a?(Numeric) && value.to_s.strip.match?(/\A-?\d+(\.\d+)?\z/)
      value.to_s.include?(".") ? value.to_f : value.to_i
    elsif actual.is_a?(TrueClass) || actual.is_a?(FalseClass)
      value.to_s.strip.downcase.in?(["1", "true", "yes"]) ? true : (value.to_s.strip.downcase.in?(["0", "false", "no"]) ? false : value)
    else
      value
    end
  end

  def compare(actual, value, &block)
    return false if actual.nil? || value.nil?
    a, b = coerce_for_compare(actual, value)
    return false if a.nil? || b.nil?
    block.call(a, b)
  rescue ArgumentError, TypeError
    false
  end

  def coerce_for_compare(actual, value)
    v = value.is_a?(String) ? value.strip : value
    if actual.is_a?(Numeric) || (v.present? && v.to_s.match?(/\A-?\d+(\.\d+)?\z/))
      [actual.to_f, v.to_f]
    elsif actual.is_a?(Time) || actual.is_a?(DateTime) || actual.is_a?(Date)
      parsed = v.present? ? Time.zone.parse(v.to_s) : nil
      [actual.to_time, parsed].compact.size == 2 ? [actual.to_time, parsed] : [nil, nil]
    else
      [actual.to_f, v.to_f]
    end
  end
end
