module NetworkServices
  # Sends the pre-order OTP over the shop's own BSP (Meta Cloud API) WhatsApp
  # number, using the authentication template the merchant bound to the
  # `pre_order_otp` event. Returns the Meta message id on success, or nil when
  # BSP isn't usable (no verified account / no approved bound template / send
  # error) so the caller can fall back to the legacy MSG91 path.
  #
  #   message_id = NetworkServices::PreOrderOtpBspService.call(shop, phone, otp)
  class PreOrderOtpBspService < ApplicationService
    EVENT_KEY = 'pre_order_otp'.freeze

    def initialize(shop, phone, otp)
      @shop = shop
      @phone = phone
      @otp = otp
    end

    def call
      account, template = resolve_account_and_template
      return nil unless account && template

      log = Meta::SendTemplateMessageService.call(
        account: account,
        template: template,
        recipient: @phone,
        body_parameters: [{ 'type' => 'text', 'text' => @otp.to_s }],
        # Authentication templates with a COPY_CODE/one-tap button require the
        # code as the button parameter too (Meta sends it as a url-subtype param).
        button_slug: @otp.to_s,
        event_type_key: EVENT_KEY,
        payload_snapshot: { 'otp' => true, 'source' => EVENT_KEY }
      )
      log.meta_message_id
    rescue Meta::SendTemplateMessageService::Error => e
      Rails.logger.warn("[pre_order_otp] BSP send failed; falling back to MSG91: #{e.message}")
      nil
    end

    private

    # Returns [account, template] only when the shop is fully set up to send OTP
    # via BSP: a verified account that can send, plus an approved template bound
    # to the pre_order_otp event. Any gap returns [nil, nil] → MSG91 fallback.
    def resolve_account_and_template
      binding = @shop.whatsapp_template_bindings.find_by(event_type_key: EVENT_KEY)
      template = binding&.whatsapp_template
      return [nil, nil] unless template&.approved?

      # Send from the number bound to the pre_order_otp event (falls back to the
      # shop default for legacy bindings).
      account = binding&.whatsapp_account || @shop.default_whatsapp_account
      return [nil, nil] unless account&.ready_to_send?

      [account, template]
    end
  end
end
