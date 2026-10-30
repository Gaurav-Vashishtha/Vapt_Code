# frozen_string_literal: true

module CodForm
  module Engine
    # Abandoned-form recovery link and prefill (ARCHITECTURE E.13 / I.4, ABN-2).
    class Recovery
      PARAM = "codk_recover"

      class << self
        # primary_domain may be a host ("brand.hu"), an origin or a full page URL (product sessions).
        def url(primary_domain:, token:)
          base = primary_domain.to_s.strip
          base = "https://#{base}" unless base.match?(%r{\Ahttps?://}i)
          base = base.sub(%r{\Ahttp://}i, "https://")
          base, fragment = base.split("#", 2)
          base = "#{base}/" if base.match?(%r{\Ahttps://[^/?]+\z})
          separator = base.include?("?") ? "&" : "?"
          "#{base}#{separator}#{PARAM}=#{escape(token)}#{fragment ? "##{fragment}" : ''}"
        end

        # session = cod_form_sessions row as a string-keyed hash.
        # => {"contact"=>{...}, "address"=>{...}, "items"=>[...], "discount"=>{"type","value"}|nil}
        def prefill(session:, recovery_discount: nil)
          session = session.is_a?(Hash) ? session : {}
          contact = session["contact"].is_a?(Hash) ? session["contact"] : {}
          address = session["address"].is_a?(Hash) ? session["address"] : {}
          snapshot = session["cart_snapshot"].is_a?(Hash) ? session["cart_snapshot"] : {}
          items = Array(snapshot["items"]).filter_map do |item|
            next unless item.is_a?(Hash) && !item["variant_id"].to_s.empty?

            { "variant_id" => item["variant_id"].to_s, "quantity" => [item["quantity"].to_i, 1].max,
              "properties" => item["properties"].is_a?(Hash) ? item["properties"] : {} }
          end
          discount = recovery_discount.is_a?(Hash) ? recovery_discount : nil
          discount = nil unless discount && %w[percentage fixed_amount].include?(discount["type"].to_s) &&
                                discount["value"].is_a?(Numeric) && discount["value"].positive?
          {
            "contact" => {
              "phone" => contact["phone_national"].to_s, "email" => contact["email"].to_s,
              "first_name" => contact["first_name"].to_s, "last_name" => contact["last_name"].to_s
            },
            "address" => %w[country province city zip address1 address2].each_with_object({}) { |key, out| out[key] = address[key].to_s },
            "items" => items,
            "discount" => discount ? { "type" => discount["type"].to_s, "value" => discount["value"] } : nil
          }
        end

        private

        def escape(text)
          text.to_s.b.gsub(/[^A-Za-z0-9\-_.~]/n) { |char| Kernel.format("%%%02X", char.ord) }
        end
      end
    end
  end
end
