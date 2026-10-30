# frozen_string_literal: true

module CodForm
  # OTP step of the form (ARCHITECTURE.md D.4, D.5, F.7). Wraps the existing
  # NetworkServices::SendPreOrderOtpService / VerifyPreOrderOtpService unchanged; the session's
  # public_id is the `device_id`, so the verified order links to its PreOrderOtp row (F8).
  # No `cart_details` is passed: form sessions stay out of the OTP abandoned-cart pipeline (F12).
  class OtpService
    DEFAULT_MAX_SENDS = 3
    DEFAULT_RESEND_WAIT = 30
    MAX_FAILED_VERIFIES = 5
    CODE_LENGTH = 4

    class << self
      # The "otp" block of the session response (D.1).
      # OTP in the form has a switch of its own on the COD Form's Fraud screen
      # (general.otp.enabled, off until the merchant turns it on), and its own channel, number
      # of sends and resend wait (general.otp.whatsapp / max_attempts / resend_wait_seconds).
      # Nothing is read from the store-wide pre-order OTP screen, which is Express checkout only.
      # Only the message text itself is the store's messaging template (sent by the shared
      # NetworkServices sender).
      # A form that asks for the phone number first always has OTP: that step is an OTP step.
      def enabled_for?(setting, form_config, general = nil)
        return true if form_config.is_a?(Hash) && form_config.dig("steps", "phone_first") == true

        on?(setting, general)
      end

      # The same answer without a form (order-first OTP, risk-based OTP).
      def on?(setting, general)
        general.is_a?(Hash) && general.dig("otp", "enabled") == true
      end

      def settings(setting, general, form_config = nil)
        channels = ["sms"]
        channels << "whatsapp" if whatsapp?(general)
        {
          "enabled" => enabled_for?(setting, form_config, general),
          "mode" => general.dig("otp", "mode").to_s.presence || "before_order",
          "channels" => channels,
          "max_attempts" => max_sends(general),
          "resend_wait_seconds" => resend_wait(general),
          "code_length" => CODE_LENGTH
        }
      end

      # => D.4 response body (string keys). Raises CodForm::Errors::ApiError.
      def send_code(session:, phone:, country:, channel:, ip:, shop: nil, config: nil)
        shop ||= Shop.find(session.shop_id)
        config ||= CodForm::ShopConfig.for(shop)
        setting = shop.setting
        country = country.to_s.strip.upcase
        general = config.general
        channel = channel.to_s == "whatsapp" && whatsapp?(general) ? "whatsapp" : "sms"

        # 1. phone
        parsed = CodForm::Engine::Phone.validate(
          raw: phone.to_s[0, 40], country: country, rules: CodForm::Engine::CountrySchema.phone_rules(country: country)
        )
        raise CodForm::Errors.build("validation_failed", fields: { "phone" => "error_phone" }) unless parsed["valid"] == true

        contact = { "phone_digits" => parsed["digits"], "phone_national" => parsed["national"], "email" => session.email_normalized.to_s }

        # 2. block list + per-phone limiter
        check = CodForm::FraudAdapter.check(
          shop: shop, config: config, contact: contact, ip: ip, cart: {}, timing: nil, is_test: session.is_test
        )
        if check["code"] == "blocked"
          CodForm::FraudAdapter.record_rejection(shop: shop, session: session, reason: check["reason"], stage: "otp", contact: contact, ip: ip)
          raise CodForm::Errors.build("blocked", message: check["message"])
        end
        limit, period = CodForm::RateLimiter.default_limit("otp_phone")
        unless CodForm::RateLimiter.hit!(CodForm::RateLimiter.otp_key(shop.id, parsed["digits"]), limit: limit, period: period)
          raise CodForm::Errors.build("otp_throttled", retry_after: CodForm::RateLimiter.retry_after(period))
        end

        # 3. sends per session (OTP-2)
        otp = session.otp.is_a?(Hash) ? session.otp.dup : {}
        max = max_sends(general)
        raise CodForm::Errors.build("otp_attempts_exceeded") if otp["sends"].to_i >= max

        last_sent = parse_time(otp["last_sent_at"])
        wait = resend_wait(general)
        if last_sent && (Time.current - last_sent) < wait
          raise CodForm::Errors.build("otp_throttled", retry_after: (wait - (Time.current - last_sent)).ceil)
        end

        # 4. the existing service, unchanged
        result = NetworkServices::SendPreOrderOtpService.call(
          shop.id,
          { "country_code" => country, "phone" => parsed["national"], "mode" => (channel == "whatsapp" ? "WHATSAPP" : "SMS"),
            "ip_address" => ip.to_s, "device_id" => session.public_id }
        )

        # 5. map the result
        status = read(result, "status").to_s
        code = read(result, "code").to_s
        if code == "pre_order_otp_throttled"
          raise CodForm::Errors.build("otp_throttled", retry_after: 60)
        elsif code == "pre_order_otp_phone_blocked"
          CodForm::FraudAdapter.record_rejection(shop: shop, session: session, reason: "phone_blocked", stage: "otp", contact: contact, ip: ip)
          raise CodForm::Errors.build("blocked")
        elsif status != "Success"
          return bypass!(shop, session, otp, channel)
        end

        # 6. session
        otp.merge!("sends" => otp["sends"].to_i + 1, "channel" => channel, "last_sent_at" => Time.current.utc.iso8601,
                   "phone_digits" => parsed["digits"], "failed_verifies" => 0)
        otp.delete("bypassed")
        attrs = { otp: otp, updated_at: Time.current }
        attrs[:status] = CodForm::Session::STATUS_OTP_PENDING if CodForm::Session::ORDERABLE_STATUSES.include?(session.status)
        session.update_columns(attrs)
        CodForm::FunnelLogger.log(shop_id: shop.id, session_token: session.public_id, type: "cf_otp_sent", meta: { "channel" => channel })

        {
          "ok" => true, "sent" => true, "channel" => channel, "resend_wait_seconds" => wait,
          "attempts_left" => [max - otp["sends"], 0].max, "masked_phone" => mask_phone(parsed["e164"])
        }
      end

      # => D.5 response body. Raises CodForm::Errors::ApiError.
      def verify(session:, phone:, country:, code:, ip:, shop: nil, phone_first: false)
        shop ||= Shop.find(session.shop_id)
        country = country.to_s.strip.upcase
        parsed = CodForm::Engine::Phone.validate(
          raw: phone.to_s[0, 40], country: country, rules: CodForm::Engine::CountrySchema.phone_rules(country: country)
        )
        raise CodForm::Errors.build("validation_failed", fields: { "phone" => "error_phone" }) unless parsed["valid"] == true

        code = code.to_s.strip
        otp = session.otp.is_a?(Hash) ? session.otp.dup : {}
        raise CodForm::Errors.build("otp_attempts_exceeded") if otp["failed_verifies"].to_i >= MAX_FAILED_VERIFIES

        limit, period = CodForm::RateLimiter.default_limit("otp_verify")
        unless CodForm::RateLimiter.hit!("codf:otpv:#{session.public_id}", limit: limit, period: period)
          raise CodForm::Errors.build("otp_throttled", retry_after: CodForm::RateLimiter.retry_after(period))
        end
        return wrong_code!(session, otp) unless code.match?(/\A\d{4,8}\z/)

        result = NetworkServices::VerifyPreOrderOtpService.call(
          shop.id,
          { "country_code" => country, "phone" => parsed["national"], "otp" => code, "ip_address" => ip.to_s,
            "device_id" => session.public_id, "email" => session.email_normalized.to_s.presence }
        )
        return wrong_code!(session, otp) unless read(result, "verification") == true

        contact = (session.contact.is_a?(Hash) ? session.contact : {}).merge(
          "phone_e164" => parsed["e164"], "phone_national" => parsed["national"]
        )
        otp["failed_verifies"] = 0
        otp["verified_digits"] = parsed["digits"]
        attrs = { otp_verified_at: Time.current, contact: contact, phone_normalized: parsed["digits"], otp: otp, updated_at: Time.current }
        attrs[:status] = CodForm::Session::STATUS_OPEN if session.status == CodForm::Session::STATUS_OTP_PENDING
        session.update_columns(attrs)
        CodForm::FunnelLogger.log(shop_id: shop.id, session_token: session.public_id, type: "cf_otp_verified", meta: {})

        tag_verified_order(shop, session) if session.order_id.present? # OTP "order first" (F.7)

        body = { "ok" => true, "verified" => true }
        # FRM-18: saved addresses only in phone-first mode, only after a successful verification.
        # customerLogin and sso_session_token are discarded; no cookie is set.
        if phone_first
          saved = saved_addresses(read(result, "shippingAddress"), country)
          body["saved_addresses"] = saved unless saved.empty?
        end
        body
      end

      SAVED_ADDRESS_KEYS = %w[first_name last_name address1 address2 city zip].freeze
      MAX_SAVED_ADDRESSES = 3

      # The existing service answers with `customer_addresses` rows (as_json). The form gets only
      # the fields it has inputs for, keyed like its own values: `province` is the province CODE
      # (the row's `province` is a name), and rows of another country are left out — the row's
      # `country` is a name and must never reach the form's country field.
      def saved_addresses(raw, country)
        raw = raw.as_json if raw.respond_to?(:as_json)
        rows = raw.is_a?(Hash) ? [raw] : Array(raw)
        rows.filter_map do |row|
          next unless row.is_a?(Hash)

          row = row.transform_keys(&:to_s)
          row_country = (row["country_code"].presence || row["country_code_v2"]).to_s.upcase
          next unless row_country.empty? || row_country == country.to_s.upcase

          out = SAVED_ADDRESS_KEYS.to_h { |key| [key, row[key].to_s.strip[0, 255]] }
          out["province"] = row["province_code"].to_s.strip[0, 20]
          out.reject { |_, value| value.empty? }.presence
        end.first(MAX_SAVED_ADDRESSES)
      end

      def whatsapp?(general)
        general.is_a?(Hash) && general.dig("otp", "whatsapp") == true
      end

      def max_sends(general)
        value = general.is_a?(Hash) ? general.dig("otp", "max_attempts") : nil
        value.is_a?(Integer) ? value.clamp(1, 5) : DEFAULT_MAX_SENDS
      end

      def resend_wait(general)
        value = general.is_a?(Hash) ? general.dig("otp", "resend_wait_seconds") : nil
        value.is_a?(Integer) && value.positive? ? value : DEFAULT_RESEND_WAIT
      end

      # "+36301234567" => "+36 •• ••• 4567" style: dial prefix and last four digits only.
      def mask_phone(e164)
        digits = e164.to_s.gsub(/\D/, "")
        return "" if digits.length < 6

        "+#{digits[0, 2]} #{'•' * (digits.length - 6)} #{digits[-4, 4]}"
      end

      private

      # The existing services answer with symbol or string keys depending on the branch.
      def read(result, key)
        return nil unless result.is_a?(Hash)

        result.key?(key) ? result[key] : result[key.to_sym]
      end

      def parse_time(value)
        value.to_s.empty? ? nil : Time.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end

      # Decision 15: a send failure on our side never costs the buyer the order. The order is
      # created unverified and gets the shop's post-order verification (F.5).
      def bypass!(shop, session, otp, channel)
        otp.merge!("bypassed" => true, "channel" => channel, "last_sent_at" => Time.current.utc.iso8601)
        session.update_columns(otp: otp, updated_at: Time.current)
        CodForm::FunnelLogger.log(shop_id: shop.id, session_token: session.public_id, type: "cf_otp_bypassed",
                                  meta: { "reason" => "otp_unavailable" })
        begin
          CodForm::OtpUnavailableNotifyJob.perform_async(shop.id)
        rescue StandardError => e
          Rails.logger.warn("[CodForm::OtpService] notify enqueue failed shop_id=#{shop.id} #{e.class}")
        end
        { "ok" => true, "sent" => false, "bypass" => true }
      end

      def wrong_code!(session, otp)
        otp["failed_verifies"] = otp["failed_verifies"].to_i + 1
        session.update_columns(otp: otp, updated_at: Time.current)
        left = [MAX_FAILED_VERIFIES - otp["failed_verifies"], 0].max
        raise CodForm::Errors.build("otp_attempts_exceeded") if left.zero?

        raise CodForm::Errors.build("otp_invalid", extra: { "attempts_left" => left })
      end

      # F.7: the order exists already; add the verification tag and mark the confirmation.
      def tag_verified_order(shop, session)
        tag = shop.setting&.verification_tag.presence || "✅ COD-Verified"
        ShopifyServices::OrderTagPostService.call(shop, session.order_id, tag)
        OrderConfirmation.where(shop_id: shop.id, order_id: session.order_id).update_all(status: "COD-Verified", updated_at: Time.current)
      rescue StandardError => e
        Rails.logger.error("[CodForm::OtpService] order-first tagging failed shop_id=#{shop.id} order_id=#{session.order_id} #{e.class}")
      end
    end
  end
end
