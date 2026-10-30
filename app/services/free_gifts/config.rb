# frozen_string_literal: true

module FreeGifts
  module Config
    TRIGGERS = %w[cart_range cart_items product collection].freeze
    MATCHES = %w[any all].freeze
    MAX_RULES = 20
    MAX_PRODUCTS = 50
    MAX_COLLECTIONS = 10
    MAX_COLLECTION_PRODUCTS = 500
    MAX_GIFT_QUANTITY = 10
    MAX_TEXT = 120
    DEFAULTS = {
      "enabled" => false,
      "stacking" => false,
      "remove_when_ineligible" => true,
      "show_progress" => true,
      "progress_message" => "Add {remaining} more to get {gift} free",
      "unlocked_message" => "You've unlocked a free {gift}!",
      "badge_label" => "Free"
    }.freeze
    BOOLEAN_KEYS = %w[enabled stacking remove_when_ineligible show_progress].freeze
    TEXT_KEYS = %w[progress_message unlocked_message badge_label].freeze

    module_function

    def sanitize(raw)
      raw = hashify(raw) || {}
      config = DEFAULTS.dup
      BOOLEAN_KEYS.each { |key| config[key] = truthy?(raw[key]) if raw.key?(key) }
      TEXT_KEYS.each do |key|
        text = raw[key].to_s.strip[0, MAX_TEXT]
        config[key] = text if text.present?
      end
      config["rules"] = sanitize_rules(raw["rules"])
      config
    end

    def sanitize_rules(rules)
      list = rules.is_a?(Hash) ? rules.values : Array(rules)
      seen = {}
      list.filter_map { |rule| sanitize_rule(rule) }
          .reject { |rule| seen[rule["id"]].tap { seen[rule["id"]] = true } }
          .first(MAX_RULES)
    end

    def sanitize_rule(raw)
      raw = hashify(raw)
      return nil unless raw

      trigger = TRIGGERS.include?(raw["trigger"].to_s) ? raw["trigger"].to_s : "cart_range"
      gift = hashify(raw["gift"]) || {}
      {
        "id" => raw["id"].to_s.match?(/\Afg_[a-z0-9]{4,24}\z/) ? raw["id"].to_s : "fg_#{SecureRandom.hex(5)}",
        "title" => raw["title"].to_s.strip[0, 80],
        "enabled" => raw.key?("enabled") ? truthy?(raw["enabled"]) : true,
        "trigger" => trigger,
        "min_amount" => trigger == "cart_range" ? amount(raw["min_amount"]) : nil,
        "max_amount" => trigger == "cart_range" ? amount(raw["max_amount"]) : nil,
        "min_items" => trigger == "cart_items" ? [raw["min_items"].to_i, 1].max : nil,
        "product_ids" => trigger == "product" ? ids(raw["product_ids"], MAX_PRODUCTS) : [],
        "match" => trigger == "product" && MATCHES.include?(raw["match"].to_s) ? raw["match"].to_s : "any",
        "collection_ids" => trigger == "collection" ? ids(raw["collection_ids"], MAX_COLLECTIONS) : [],
        "collection_product_ids" => trigger == "collection" ? ids(raw["collection_product_ids"], MAX_COLLECTION_PRODUCTS) : [],
        "min_quantity" => trigger == "collection" ? [raw["min_quantity"].to_i, 1].max : nil,
        "gift_product_id" => FreeGifts.numeric_id(raw["gift_product_id"]),
        "gift_variant_id" => FreeGifts.numeric_id(raw["gift_variant_id"]),
        "gift_quantity" => raw["gift_quantity"].to_i.clamp(1, MAX_GIFT_QUANTITY),
        "gift" => {
          "title" => gift["title"].to_s[0, 255],
          "variant_title" => gift["variant_title"].to_s[0, 255],
          "image" => gift["image"].presence,
          "price" => amount(gift["price"])
        }
      }
    end

    def errors(config)
      messages = []
      config["rules"].each_with_index do |rule, index|
        label = rule["title"].presence || "Rule #{index + 1}"
        messages << "#{label}: choose a gift product" unless rule["gift_variant_id"]
        case rule["trigger"]
        when "cart_range"
          messages << "#{label}: enter a minimum cart value" if rule["min_amount"].nil?
          if rule["max_amount"] && rule["min_amount"] && rule["max_amount"] <= rule["min_amount"]
            messages << "#{label}: maximum must be greater than minimum"
          end
        when "product"
          messages << "#{label}: select at least one product" if rule["product_ids"].empty?
        when "collection"
          messages << "#{label}: select at least one collection" if rule["collection_ids"].empty?
        end
      end
      messages + overlap_errors(config["rules"])
    end

    def overlap_errors(rules)
      ranges = rules.select { |r| r["enabled"] && r["trigger"] == "cart_range" && r["min_amount"] }
      ranges.combination(2).filter_map do |a, b|
        next unless (b["max_amount"].nil? || a["min_amount"] < b["max_amount"]) && (a["max_amount"].nil? || b["min_amount"] < a["max_amount"])

        "Cart value ranges of “#{a['title'].presence || a['id']}” and “#{b['title'].presence || b['id']}” overlap"
      end
    end

    def hashify(raw)
      raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
      raw = raw.to_h if raw.respond_to?(:to_h) && !raw.is_a?(Hash) && !raw.is_a?(Array)
      raw.is_a?(Hash) ? raw.transform_keys(&:to_s) : nil
    end

    def truthy?(value)
      value == true || value.to_s == "true"
    end

    def amount(value)
      return nil if value.blank?

      number = value.to_s.to_d
      number.negative? ? nil : number.round(2).to_f
    rescue ArgumentError
      nil
    end

    def ids(values, limit)
      Array(values).filter_map { |v| FreeGifts.numeric_id(v) }.uniq.first(limit)
    end
  end
end
