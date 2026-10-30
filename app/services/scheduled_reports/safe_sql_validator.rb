# frozen_string_literal: true

module ScheduledReports
  module SafeSqlValidator
    module_function

    FORBIDDEN = /
      \b(insert|update|delete|drop|truncate|alter|create|grant|revoke|copy|
      execute|prepare|listen|notify|load_file|into\s+outfile|pg_sleep|dblink)\b
    /ix

    # Shop binding: use {{shop_id}} or the alias {{shops.id}} (same value: internal shops.id).
    SHOP_ID_PLACEHOLDER = /\{\{\s*(?:shop_id|shops\.id)\s*\}\}/i

    def validate!(sql_text)
      sql = sql_text.to_s.strip
      raise UnsafeSqlError, "SQL cannot be blank" if sql.blank?
      raise UnsafeSqlError, "Only SELECT queries are allowed" unless sql.match?(/\A\s*select\b/i)
      raise UnsafeSqlError, "Multiple statements are not allowed" if sql.count(";") > 1
      unless sql.match?(SHOP_ID_PLACEHOLDER)
        raise UnsafeSqlError,
              "Query must include a shop placeholder, e.g. {{shop_id}} or {{shops.id}}"
      end
      raise UnsafeSqlError, "Disallowed keyword in SQL" if sql.match?(FORBIDDEN)

      sql
    end
  end
end
