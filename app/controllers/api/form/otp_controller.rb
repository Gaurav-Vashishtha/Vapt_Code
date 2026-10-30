# frozen_string_literal: true

module Api
  module Form
    # POST /api/form/otp/send and /api/form/otp/verify (D.4, D.5).
    class OtpController < BaseController
      def send_code
        result = CodForm::OtpService.send_code(
          session: form_session, phone: body["phone"], country: country, channel: body["channel"],
          ip: request.remote_ip.to_s, shop: shop, config: shop_config
        )
        render_ok(result.except("ok"))
      end

      def verify
        result = CodForm::OtpService.verify(
          session: form_session, phone: body["phone"], country: country, code: body["code"],
          ip: request.remote_ip.to_s, shop: shop, phone_first: phone_first?
        )
        render_ok(result.except("ok"))
      end

      private

      def country
        value = body["country"].to_s.strip.upcase
        value.match?(/\A[A-Z]{2}\z/) ? value : form_session.country_code.to_s
      end

      def phone_first?
        form = form_session.cod_form_id ? CodForm::Form.find_by(id: form_session.cod_form_id, shop_id: shop.id) : nil
        form&.published_config.is_a?(Hash) && form.published_config.dig("steps", "phone_first") == true
      end
    end
  end
end
