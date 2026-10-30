# frozen_string_literal: true

require "json"

unless defined?(::Rails)
  require_relative "money"
end

module CodForm
  module Engine
    # Builds the GraphQL DraftOrderInput for a form order (ARCHITECTURE F.3). The only place where
    # cents become Shopify decimals.
    class DraftOrderBuilder
      BASE_TAGS = %w[COD Created-From-COD-King codking_form].freeze
      TEST_TAG = "codking_form_test"
      NOTE_TITLE = "COD Form order"

      class << self
        # quote = Quote.build output (reads quote["_draft"]); contact = {"first_name","last_name","phone_e164","email"}
        # address = {"address1","address2","city","province","country","zip"}; meta: see F.3.
        def build(quote:, contact:, address:, meta:)
          quote = hash(quote)
          draft = hash(quote["_draft"])
          contact = hash(contact)
          address = hash(address)
          meta = hash(meta)
          currency = (draft["currency"] || quote["currency"]).to_s
          phone = text(contact["phone_e164"] || contact["phone"])
          email = text(contact["email"])
          country = text(meta["country"] || address["country"]).upcase

          line_items = Array(draft["lines"]).map { |line| line_item(line, currency) }
          fee = draft["cod_fee"]
          fee_amount = fee.is_a?(Hash) ? fee["amount_cents"].to_i : 0
          if fee_amount.positive?
            line_items << {
              "title" => text(fee["label"]).empty? ? "Cash on delivery fee" : text(fee["label"]), "quantity" => 1,
              "originalUnitPriceWithCurrency" => money(fee_amount, currency),
              "requiresShipping" => false, "taxable" => fee["taxable"] == true,
              "customAttributes" => [{ "key" => "_codk_line", "value" => "cod_fee" }]
            }
          end

          # The store's automatic discounts are already in the quote as explicit line / order
          # discounts (CodForm::AutomaticDiscountService), so Shopify must not add them again.
          input = { "lineItems" => line_items, "acceptAutomaticDiscounts" => false }

          discount = draft["order_discount"]
          if discount.is_a?(Hash) && discount["amount_cents"].to_i.positive?
            title = text(discount["title"] || discount["code"])
            input["appliedDiscount"] = { "valueType" => "FIXED_AMOUNT", "value" => decimal(discount["amount_cents"]),
                                         "title" => title, "description" => text(discount["description"]).empty? ? "Discount code #{title}" : text(discount["description"]) }
          end

          shipping = draft["shipping"]
          if shipping.is_a?(Hash)
            input["shippingLine"] = { "title" => text(shipping["title"]),
                                      "priceWithCurrency" => money(shipping["price_cents"].to_i, currency) }
          end

          mailing = mailing_address(contact, address, country, phone)
          input["shippingAddress"] = mailing
          input["billingAddress"] = mailing.dup
          input["email"] = email.empty? ? nil : email
          input["phone"] = phone.empty? ? nil : phone
          customer = text(meta["customer_gid"])
          input["purchasingEntity"] = { "customerId" => customer } unless customer.empty?
          input["presentmentCurrencyCode"] = currency
          input["taxExempt"] = false
          input["note"] = note(meta)
          input["tags"] = tags(meta)
          input["customAttributes"] = custom_attributes(meta, fee_amount, country)
          input
        end

        private

        def hash(value)
          value.is_a?(Hash) ? value : {}
        end

        def text(value)
          value.nil? ? "" : value.to_s.strip
        end

        def money(cents, currency)
          { "amount" => Money.to_decimal_string(cents), "currencyCode" => currency }
        end

        # 50000 => 500.0 (GraphQL Float)
        def decimal(cents)
          cents.to_i / 100.0
        end

        def line_item(line, currency)
          kind = line["kind"].to_s
          attributes = hash(line["properties"]).map { |key, value| { "key" => key.to_s, "value" => value.to_s } }
          marker = case kind
                   when "bump", "custom_bump" then "bump:#{line['offer_id']}"
                   when "gift" then "gift:#{line['offer_id']}"
                   when "pre_upsell" then "pre_upsell:#{line['offer_id']}"
                   end
          attributes << { "key" => "_codk_line", "value" => marker } if marker

          if kind == "custom_bump"
            return { "title" => text(line["title"]), "quantity" => line["quantity"].to_i,
                     "originalUnitPriceWithCurrency" => money(line["unit_price_cents"].to_i, currency),
                     "requiresShipping" => line["requires_shipping"] == true, "taxable" => line["taxable"] != false,
                     "customAttributes" => attributes }
          end

          item = { "variantId" => "gid://shopify/ProductVariant/#{line['variant_id']}", "quantity" => line["quantity"].to_i }
          unit_discount = line["unit_discount_cents"].to_i
          title = text(line["discount_title"])
          if kind == "gift"
            title = "Free gift" if title.empty?
            item["appliedDiscount"] = { "valueType" => "PERCENTAGE", "value" => 100.0, "title" => title, "description" => title }
          elsif unit_discount.positive?
            title = "Discount" if title.empty?
            item["appliedDiscount"] =
              if line["discount_value_type"].to_s == "percentage" && line["discount_percent"].is_a?(Numeric)
                { "valueType" => "PERCENTAGE", "value" => line["discount_percent"].to_f, "title" => title, "description" => title }
              else
                { "valueType" => "FIXED_AMOUNT", "value" => decimal(unit_discount), "title" => title, "description" => title }
              end
          end
          item["customAttributes"] = attributes unless attributes.empty?
          item
        end

        def mailing_address(contact, address, country, phone)
          province = text(address["province"]).upcase.sub(/\A#{Regexp.escape(country)}-/, "")
          out = {
            "firstName" => text(contact["first_name"]), "lastName" => text(contact["last_name"]),
            "address1" => text(address["address1"]), "address2" => text(address["address2"]),
            "city" => text(address["city"]), "provinceCode" => province, "countryCode" => country,
            "zip" => text(address["zip"]), "phone" => phone
          }
          out.reject { |key, value| value.empty? && %w[lastName address2 provinceCode zip phone].include?(key) }
        end

        def note(meta)
          fields = hash(meta["note_fields"])
          lines = [NOTE_TITLE]
          lines << "Note: #{text(fields['note'])}" unless text(fields["note"]).empty?
          lines << "GST: #{text(fields['gst_number'])}" unless text(fields["gst_number"]).empty?
          lines.join("\n")
        end

        def tags(meta)
          list = BASE_TAGS.dup
          list << text(meta["verification_tag"]) if meta["verified"] == true && !text(meta["verification_tag"]).empty?
          list << TEST_TAG if meta["is_test"] == true
          list.concat(Array(meta["shop_tags"]).map { |tag| text(tag) })
          list.reject(&:empty?).uniq
        end

        def custom_attributes(meta, fee_amount, country)
          session_id = text(meta["session_id"])
          list = [
            { "key" => "_codkFormSessionId", "value" => session_id },
            { "key" => "_codkFormId", "value" => text(meta["form_id"]) },
            { "key" => "_codkCodFee", "value" => Money.to_decimal_string(fee_amount) },
            { "key" => "_codkSessionId", "value" => session_id }
          ]
          otp_phone = text(meta["otp_phone_e164"])
          list << { "key" => "_otpVerifiedPhoneNumber", "value" => otp_phone } if meta["verified"] == true && !otp_phone.empty?
          list << { "key" => "_codkCountryCode", "value" => country } unless country.empty?
          list << { "key" => "_codkFormTest", "value" => "true" } if meta["is_test"] == true
          attribution = hash(meta["attribution"]).reject { |_, value| text(value).empty? }
          list << { "key" => "_codk_campaign_json", "value" => JSON.generate(attribution) } unless attribution.empty?
          Array(meta["custom_fields"]).each do |field|
            next unless field.is_a?(Hash) && !text(field["label"]).empty? && !text(field["value"]).empty?

            list << { "key" => text(field["label"]), "value" => text(field["value"]) }
          end
          list
        end
      end
    end
  end
end
