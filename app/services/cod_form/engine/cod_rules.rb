# frozen_string_literal: true

unless defined?(::Rails)
  require_relative "postal_matcher"
end

module CodForm
  module Engine
    # COD rules shared with the checkout payment function (ARCHITECTURE E.3, RUL-1, VIS-6).
    class CodRules
      STAGES = %w[page quote submit].freeze

      class << self
        # => {"allowed"=>bool, "reasons"=>[...], "pending"=>[...]}
        def evaluate(rules:, cart:, address:, contact:, stage:)
          rules = hash(rules)
          cart = hash(cart)
          address = hash(address)
          contact = hash(contact)
          submit = stage.to_s == "submit"
          reasons = []
          pending = []
          lines = Array(cart["lines"]).select { |line| line.is_a?(Hash) }

          country = text(address["country"]).upcase
          province = text(address["province"]).upcase
          province = province.sub(/\A#{Regexp.escape(country)}-/, "") unless country.empty?
          zip = text(address["zip"])

          # country
          allow_countries = list(rules["allow_countries"]).map(&:upcase)
          unless allow_countries.empty?
            if country.empty?
              submit ? reasons << "country_not_allowed" : pending << "country"
            elsif !allow_countries.include?(country)
              reasons << "country_not_allowed"
            end
          end

          # provinces
          allow_provinces = list(rules["allow_provinces"]).map(&:upcase)
          deny_provinces = list(rules["deny_provinces"]).map(&:upcase)
          unless allow_provinces.empty?
            if province.empty?
              submit ? reasons << "province_not_allowed" : pending << "province"
            elsif !province_listed?(allow_provinces, country, province)
              reasons << "province_not_allowed"
            end
          end
          unless deny_provinces.empty?
            if province.empty?
              pending << "province" unless submit
            elsif province_listed?(deny_provinces, country, province)
              reasons << "province_not_allowed"
            end
          end

          # postal codes
          allow_zips = PostalMatcher.parse(rules["allow_zips"])
          deny_zips = PostalMatcher.parse(rules["deny_zips"])
          unless allow_zips.empty?
            if zip.empty?
              submit ? reasons << "zip_not_allowed" : pending << "zip"
            elsif !PostalMatcher.match?(zip, allow_zips)
              reasons << "zip_not_allowed"
            end
          end
          unless deny_zips.empty?
            if zip.empty?
              pending << "zip" unless submit
            elsif PostalMatcher.match?(zip, deny_zips)
              reasons << "zip_not_allowed"
            end
          end

          # products / variants
          product_ids = lines.map { |line| text(line["product_id"]) }
          variant_ids = lines.map { |line| text(line["variant_id"]) }
          deny_products = list(rules["deny_product_ids"])
          allow_products = list(rules["allow_product_ids"])
          deny_variants = list(rules["deny_variant_ids"])
          reasons << "product_not_allowed" if product_ids.any? { |id| deny_products.include?(id) }
          reasons << "product_not_allowed" if !allow_products.empty? && product_ids.any? { |id| !allow_products.include?(id) }
          reasons << "product_not_allowed" if variant_ids.any? { |id| deny_variants.include?(id) }
          reasons << "product_not_allowed" if truthy?(rules["hide_gift_cards"]) && lines.any? { |line| line["gift_card"] == true }

          # collections
          deny_collections = list(rules["deny_collection_ids"])
          allow_collections = list(rules["allow_collection_ids"])
          line_collections = lines.map { |line| list(line["collection_ids"]) }
          reasons << "collection_not_allowed" if line_collections.any? { |ids| (ids & deny_collections).any? }
          if !allow_collections.empty? && line_collections.any? { |ids| (ids & allow_collections).empty? }
            reasons << "collection_not_allowed"
          end

          # vendors
          vendors = lines.map { |line| text(line["vendor"]).downcase }
          deny_vendors = list(rules["deny_vendors"]).map(&:downcase)
          allow_vendors = list(rules["allow_vendors"]).map(&:downcase)
          reasons << "vendor_not_allowed" if vendors.any? { |vendor| deny_vendors.any? { |entry| vendor.include?(entry) } }
          if !allow_vendors.empty? && !lines.empty? && vendors.none? { |vendor| allow_vendors.include?(vendor) }
            reasons << "vendor_not_allowed"
          end

          # totals
          total = cart["total_cents"]
          if total.is_a?(Numeric)
            min = bound(rules["min_total_cents"])
            max = bound(rules["max_total_cents"])
            reasons << "total_out_of_range" if (min && total < min) || (max && total > max)
          end

          # buyer
          digits = text(contact["phone_digits"]).gsub(/\D/, "")
          deny_phones = list(rules["deny_phones"]).map { |entry| entry.gsub(/\D/, "") }.reject(&:empty?)
          reasons << "phone_blocked" if !digits.empty? && deny_phones.any? { |entry| digits.include?(entry) }
          email = text(contact["email"]).downcase
          deny_emails = list(rules["deny_emails"]).map(&:downcase)
          reasons << "email_blocked" if !email.empty? && deny_emails.any? { |entry| email.include?(entry) }

          reasons.uniq!
          { "allowed" => reasons.empty?, "reasons" => reasons, "pending" => pending.uniq }
        end

        private

        def hash(value)
          value.is_a?(Hash) ? value : {}
        end

        def text(value)
          value.nil? ? "" : value.to_s.strip
        end

        # Accepts an Array or a comma-separated String; blanks dropped.
        def list(value)
          items = value.is_a?(Array) ? value : value.to_s.split(",")
          items.map { |item| text(item) }.reject(&:empty?)
        end

        def truthy?(value)
          value == true || value.to_s == "true"
        end

        def bound(value)
          return nil if value.nil?

          number = value.is_a?(Numeric) ? value : Float(value.to_s, exception: false)
          number && number.positive? ? number : nil
        end

        def province_listed?(entries, country, province)
          entries.include?(province) || (!country.empty? && entries.include?("#{country}-#{province}"))
        end
      end
    end
  end
end
