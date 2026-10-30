# frozen_string_literal: true

module CodForm
  # Builds the `entries` and `counts` inputs of CodForm::Engine::Fraud from the database
  # (indexed lookups only) and records rejections (ARCHITECTURE.md F.1, E.9, FRD-1..6).
  class FraudAdapter
    SUBJECT_KIND = {
      "phone_blocked" => "phone", "phone_limit" => "phone", "email_blocked" => "email", "email_limit" => "email",
      "ip_blocked" => "ip", "ip_limit" => "ip", "honeypot" => "bot", "too_fast" => "bot", "max_quantity" => "product"
    }.freeze
    # A quote has no submit timing: these values never trip the bot checks.
    NO_TIMING = nil

    class << self
      # contact = {"phone_digits","phone_national","email"}; cart = {"lines"=>[...]} ; timing = E.9 or nil.
      # => Engine::Fraud.check result.
      def check(shop:, config:, contact:, ip:, cart:, timing:, is_test:, flags: nil, fraud: nil)
        flags ||= CodForm::Gates.flags(shop)
        fraud ||= CodForm::QuoteService.fraud_settings(config)
        contact = contact.is_a?(Hash) ? contact : {}

        CodForm::Engine::Fraud.check(
          fraud: fraud,
          entries: flags["block_lists"] == true && !is_test ? entries(shop, contact, ip) : {},
          counts: flags["velocity_limits"] == true && !is_test ? counts(shop, fraud, contact, ip) : {},
          contact: contact, ip: ip.to_s, cart: cart, timing: timing, is_test: is_test ? true : false
        )
      end

      # Candidate block entries only: exact matches for phone / email, plus every CIDR entry.
      def entries(shop, contact, ip)
        scope = CodForm::BlockEntry.where(shop_id: shop.id)
        phones = [contact["phone_digits"], contact["phone_national"]].map { |v| CodForm::BlockEntry.normalize("phone", v) }.reject(&:empty?).uniq
        email = CodForm::BlockEntry.normalize("email", contact["email"])
        emails = email.empty? ? [] : [email, "*@#{email.split('@', 2).last}"]
        ip = ip.to_s.strip

        {
          "phone" => phones.empty? ? [] : scope.where(kind: "phone", value_normalized: phones).pluck(:value_normalized),
          "email" => emails.empty? ? [] : scope.where(kind: "email", value_normalized: emails).pluck(:value_normalized),
          "ip" => ip.empty? ? [] : scope.where(kind: "ip").where("value_normalized = ? OR value_normalized LIKE ?", ip, "%/%").pluck(:value_normalized)
        }
      end

      # Orders by this phone / email / ip inside each enabled window (test orders never count).
      def counts(shop, fraud, contact, ip)
        limits = fraud["limits"].is_a?(Hash) ? fraud["limits"] : {}
        subjects = {
          "phone" => [:phone_normalized, CodForm::BlockEntry.normalize("phone", contact["phone_digits"])],
          "email" => [:email_normalized, contact["email"].to_s.strip.downcase],
          "ip" => [:ip, ip.to_s.strip]
        }
        subjects.each_with_object({}) do |(kind, (column, value)), out|
          limit = limits[kind].is_a?(Hash) ? limits[kind] : {}
          next unless limit["enabled"] == true && !value.empty?

          hours = limit["window_hours"].to_f
          hours = 24.0 unless hours.positive?
          out[kind] = CodForm::Session.live.where(shop_id: shop.id, column => value)
                                      .where.not(order_id: nil)
                                      .where("ordered_at >= ?", Time.current - hours.hours).count
        end
      end

      # FRD-6. Never raises; stores only a masked subject.
      def record_rejection(shop:, session:, reason:, stage:, contact: nil, ip: nil, detail: nil)
        kind = SUBJECT_KIND[reason.to_s]
        contact = contact.is_a?(Hash) ? contact : {}
        subject =
          case kind
          when "phone" then contact["phone_digits"]
          when "email" then contact["email"]
          when "ip" then ip
          end
        CodForm::Rejection.create!(
          shop_id: shop.id,
          session_public_id: session&.public_id,
          reason_code: reason.to_s,
          stage: stage.to_s,
          subject_kind: kind,
          subject_masked: subject.to_s.empty? ? nil : CodForm::Engine::Fraud.mask(kind, subject),
          detail: detail.is_a?(Hash) ? detail : {},
          ip: ip.to_s.presence
        )
        CodForm::FunnelLogger.log(shop_id: shop.id, session_token: session.public_id, type: "cf_blocked",
                                  meta: { "reason" => reason.to_s, "stage" => stage.to_s }) if session
      rescue StandardError => e
        Rails.logger.warn("[CodForm::FraudAdapter] rejection not recorded shop_id=#{shop.id} #{e.class}")
      end
    end
  end
end
