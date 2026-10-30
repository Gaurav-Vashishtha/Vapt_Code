# frozen_string_literal: true

unless defined?(::Rails)
  require_relative "money"
  require_relative "default_labels"
end

module CodForm
  module Engine
    # Thank-you step (ARCHITECTURE E.13 / C.2, TY-1).
    class ThankYou
      TYPES = %w[order_status custom_url message whatsapp].freeze
      VARIABLES = %w[order_name order_number order_id total first_name last_name phone email].freeze

      class << self
        # config = the form config (C.2) or its "thank_you" hash.
        # order = {"id","name","number","total_cents","total_formatted","status_url"}
        # contact = {"first_name","last_name","phone_e164"|"phone","email"}
        # => {"type","url","message","whatsapp_url"}
        def resolve(config:, locale:, order:, contact:)
          config = config.is_a?(Hash) ? config : {}
          config = config["thank_you"] if config["thank_you"].is_a?(Hash)
          order = order.is_a?(Hash) ? order : {}
          contact = contact.is_a?(Hash) ? contact : {}
          values = variables(order, contact)
          type = TYPES.include?(config["type"].to_s) ? config["type"].to_s : "order_status"
          message = substitute(localized(DefaultLabels.localize(config["message"]), locale), values, false)
          message = nil if message.to_s.empty?
          status_url = order["status_url"].to_s.strip

          case type
          when "custom_url"
            url = substitute(config["url"].to_s.strip, values, true)
            return result("custom_url", url, nil, nil) if url.match?(%r{\Ahttps://}i)
          when "whatsapp"
            whatsapp = config["whatsapp"].is_a?(Hash) ? config["whatsapp"] : {}
            phone = whatsapp["phone"].to_s.gsub(/\D/, "")
            unless phone.empty?
              text = substitute(localized(DefaultLabels.localize(whatsapp["message"]), locale).to_s, values, false)
              return result("whatsapp", nil, message, "https://wa.me/#{phone}?text=#{escape(text)}")
            end
          when "message"
            return result("message", nil, message, nil)
          end

          # order_status, or a custom target that cannot be used
          return result("order_status", status_url, nil, nil) unless status_url.empty?

          # no status URL: the in-form message; nil => the client shows its default thank_you_message
          result("message", nil, message, nil)
        end

        private

        def result(type, url, message, whatsapp_url)
          { "type" => type, "url" => url.to_s.empty? ? nil : url, "message" => message, "whatsapp_url" => whatsapp_url }
        end

        def variables(order, contact)
          total = order["total_formatted"].to_s
          total = Money.to_decimal_string(order["total_cents"]) if total.empty? && order["total_cents"].is_a?(Numeric)
          {
            "order_name" => order["name"].to_s, "order_number" => order["number"].to_s, "order_id" => order["id"].to_s,
            "total" => total, "first_name" => contact["first_name"].to_s, "last_name" => contact["last_name"].to_s,
            "phone" => (contact["phone_e164"] || contact["phone"]).to_s, "email" => contact["email"].to_s
          }
        end

        def substitute(text, values, url_encode)
          text.to_s.gsub(/\{(#{VARIABLES.join('|')})\}/) do
            value = values[Regexp.last_match(1)].to_s
            url_encode ? escape(value) : value
          end
        end

        def localized(map, locale)
          return map.to_s unless map.is_a?(Hash)

          keys = [locale.to_s, locale.to_s.split(/[-_]/).first.to_s, "en", "default"].reject(&:empty?)
          keys.each do |key|
            text = map[key].to_s
            return text unless text.strip.empty?
          end
          map.values.map(&:to_s).find { |text| !text.strip.empty? }.to_s
        end

        def escape(text)
          text.to_s.b.gsub(/[^A-Za-z0-9\-_.~]/n) { |char| Kernel.format("%%%02X", char.ord) }
        end
      end
    end
  end
end
