# frozen_string_literal: true

module CodForm
  module Engine
    # Block lists, velocity limits, max quantity and bot checks (ARCHITECTURE E.9 / C.5, FRD-1..5).
    class Fraud
      KINDS = %w[phone email ip].freeze

      class << self
        # => {"ok"=>bool, "code"=>nil|"blocked"|"limit_reached"|"bot_suspected", "reason"=>nil|String, "message"=>String|nil}
        def check(fraud:, entries:, counts:, contact:, ip:, cart:, timing:, is_test:)
          fraud = hash(fraud)
          entries = hash(entries)
          counts = hash(counts)
          contact = hash(contact)
          cart = hash(cart)

          bot = bot_reason(fraud, timing)
          return result("bot_suspected", bot, nil) if bot

          unless is_test == true
            blocked = block_reason(entries, contact, ip)
            return result("blocked", blocked, message(fraud["blocked_message"])) if blocked
          end

          max = fraud["max_quantity_per_order"]
          if max.is_a?(Numeric) && max.positive? && total_quantity(cart) > max
            return result("limit_reached", "max_quantity", message(fraud["max_quantity_message"]))
          end

          unless is_test == true
            limits = hash(fraud["limits"])
            KINDS.each do |kind|
              limit = hash(limits[kind])
              next unless limit["enabled"] == true

              max_orders = limit["max_orders"]
              next unless max_orders.is_a?(Numeric) && max_orders.positive?
              next if subject(kind, contact, ip).empty?

              if counts[kind].to_i >= max_orders
                return result("limit_reached", "#{kind}_limit", message(fraud["limit_message"]))
              end
            end
          end

          { "ok" => true, "code" => nil, "reason" => nil, "message" => nil }
        end

        # Masked subject for cod_form_rejections ("+36•••••4521", "a•••@x.com").
        def mask(kind, value)
          text = value.to_s.strip
          return "" if text.empty?

          case kind.to_s
          when "phone"
            digits = text.gsub(/\D/, "")
            return "•" * digits.length if digits.length <= 4

            head = digits.length > 6 ? digits[0, 2] : ""
            "+#{head}#{'•' * (digits.length - head.length - 4)}#{digits[-4, 4]}"
          when "email"
            local, domain = text.split("@", 2)
            return "#{text[0]}•••" if domain.nil?

            "#{local[0]}•••@#{domain}"
          when "ip"
            parts = text.split(".")
            parts.length == 4 ? "#{parts[0]}.#{parts[1]}.•.•" : "#{text[0, 4]}•••"
          else
            text.length <= 2 ? "••" : "#{text[0, 2]}•••"
          end
        end

        def phone_match?(entry, digits, national)
          wanted = entry.to_s.gsub(/\D/, "").sub(/\A0+/, "")
          return false if wanted.empty?

          [digits, national].any? do |candidate|
            value = candidate.to_s.gsub(/\D/, "").sub(/\A0+/, "")
            !value.empty? && value == wanted
          end
        end

        def email_match?(entry, email)
          pattern = entry.to_s.strip.downcase
          value = email.to_s.strip.downcase
          return false if pattern.empty? || value.empty?
          return value.end_with?(pattern[1..]) && value.length > pattern.length - 1 if pattern.start_with?("*@")

          pattern == value
        end

        def ip_match?(entry, ip)
          pattern = entry.to_s.strip.downcase
          value = ip.to_s.strip.downcase
          return false if pattern.empty? || value.empty?
          return pattern == value unless pattern.include?("/")

          network, bits = pattern.split("/", 2)
          return false unless bits.match?(/\A\d{1,2}\z/) && bits.to_i <= 32

          net = ipv4_to_i(network)
          addr = ipv4_to_i(value)
          return false if net.nil? || addr.nil?

          mask = bits.to_i.zero? ? 0 : (0xFFFFFFFF << (32 - bits.to_i)) & 0xFFFFFFFF
          (net & mask) == (addr & mask)
        end

        private

        def hash(value)
          value.is_a?(Hash) ? value : {}
        end

        def result(code, reason, message)
          { "ok" => false, "code" => code, "reason" => reason, "message" => message }
        end

        def message(value)
          text = value.to_s.strip
          text.empty? ? nil : text
        end

        def bot_reason(fraud, timing)
          return nil unless timing.is_a?(Hash)
          return "honeypot" if fraud["honeypot"] != false && !timing["honeypot_value"].to_s.strip.empty?

          seconds = fraud["min_submit_seconds"]
          times = [timing["elapsed_ms"], timing["token_age_ms"]].select { |value| value.is_a?(Numeric) }
          if seconds.is_a?(Numeric) && seconds.positive? && !times.empty? && times.min < seconds * 1000
            return "too_fast"
          end

          nil
        end

        def block_reason(entries, contact, ip)
          digits = contact["phone_digits"]
          national = contact["phone_national"]
          return "phone_blocked" if Array(entries["phone"]).any? { |entry| phone_match?(entry, digits, national) }
          return "email_blocked" if Array(entries["email"]).any? { |entry| email_match?(entry, contact["email"]) }
          return "ip_blocked" if Array(entries["ip"]).any? { |entry| ip_match?(entry, ip) }

          nil
        end

        def subject(kind, contact, ip)
          case kind
          when "phone" then contact["phone_digits"].to_s.strip
          when "email" then contact["email"].to_s.strip
          else ip.to_s.strip
          end
        end

        def total_quantity(cart)
          return cart["total_quantity"].to_i if cart["total_quantity"].is_a?(Numeric)

          Array(cart["lines"]).sum { |line| line.is_a?(Hash) ? line["quantity"].to_i : 0 }
        end

        def ipv4_to_i(text)
          parts = text.to_s.split(".")
          return nil unless parts.length == 4 && parts.all? { |part| part.match?(/\A\d{1,3}\z/) && part.to_i <= 255 }

          parts.reduce(0) { |sum, part| (sum << 8) + part.to_i }
        end
      end
    end
  end
end
