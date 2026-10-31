module NetworkServices
  # Sends the COD-to-prepaid reminder over the MERCHANT'S OWN WhatsApp Business
  # Account (BSP), reusing the exact discount / order-amount / payment-link math
  # of the legacy MSG91 path (NetworkServices::WhatsappPrepaidService). Only the
  # send channel differs: it goes through Meta::SendTemplateMessageService using
  # the merchant's approved template instead of the shared MSG91 number.
  #
  # The merchant's prepaid template must expose the same 4 body variables in
  # order — {{1}} store name, {{2}} order number, {{3}} order total, {{4}} prepaid
  # total — and a dynamic URL button with base `https://cutt.ly/` (the payment
  # link slug is supplied at send time, same as the abandoned-cart BSP flow).
  class WhatsappPrepaidBspService < ApplicationService
    def initialize(shop, order_confirmation, reminder: nil, send_key: nil)
      @shop = shop
      @order_confirmation = order_confirmation
      @reminder = reminder
      @send_key = send_key
    end

    def self.eligible?(shop, reminder = nil)
      return false if paused?(shop)

      account, template = resolve_account_and_template(shop, reminder)
      account&.ready_to_send? && template&.approved?
    end

    # Resolves the [account, template] pair to send from. An explicit template
    # id (reminder or setting) wins and sends from THAT template's own account;
    # otherwise use the cod_to_prepaid binding, whose account is the number the
    # merchant routed the event to (falling back to the template's account, then
    # the shop default).
    def self.resolve_account_and_template(shop, reminder)
      id = (reminder && reminder["bsp_template_id"]).presence || shop.setting&.bsp_prepaid_template_id
      if id.present?
        template = shop.whatsapp_templates.find_by(id: id)
        return [template&.whatsapp_account, template] if template
      end

      binding = WhatsappTemplateBinding
                .for_event('cod_to_prepaid')
                .ordered_by_stage
                .find_by(shop_id: shop.id)
      template = binding&.whatsapp_template
      account = binding&.whatsapp_account || template&.whatsapp_account || shop.default_whatsapp_account
      [account, template]
    end

    # One switch silences every cod_to_prepaid send, including reminders that
    # name an explicit template id rather than going through the binding.
    def self.paused?(shop)
      WhatsappTemplateBinding.for_event('cod_to_prepaid').paused.exists?(shop_id: shop.id)
    end

    # Back-compat shim for any external callers of resolve_template.
    def self.resolve_template(shop, reminder)
      resolve_account_and_template(shop, reminder).last
    end

    def call
      return if @shop.setting&.locked

      oc = @order_confirmation
      return if oc.blank?
      return if self.class.paused?(@shop)

      account, template = self.class.resolve_account_and_template(@shop, @reminder)
      return unless account&.ready_to_send? && template&.approved?

      add_shipping = !!(@reminder && @reminder["add_shipping"])
      prepaid_total = ShopifyServices::PrepaidOrderService
                      .new(nil, oc.shop, oc.id)
                      .get_total_amount(
                        discount: (@reminder && @reminder["discount"]),
                        discount_type: (@reminder && @reminder["discount_type"]),
                        add_shipping: add_shipping
                      ).to_i

      payment_link = "https://#{ENV.fetch("APP_HOST", nil)}/order_confirmations/redirect_payment_link?domain=#{@shop.shopify_domain}&id=#{oc.id}"
      payment_link = ::Whatsapp::ClickTracker.wrap(
        payment_link, shop_id: @shop.id, event_type_key: 'cod_to_prepaid',
        source_external_id: "codprepaid:#{oc.id}:#{send_slug}", recipient: oc.customer_number
      )
      payment_link = NetworkServices::CutlyLinkService.call(payment_link).to_s.gsub("https://rzp.io/", "").gsub("https://cutt.ly/", "")

      # Shared payload context — used for both body-variable resolution and
      # header-media resolution below so they stay in sync.
      resolver_payload = {
        'shop' => { 'name' => @shop.owner_name.to_s },
        'order' => {
          'name' => oc.final_order_number.to_s,
          'total' => "#{oc.order_amount}₹",
          'customer' => {
            'first_name' => oc.customer_name.to_s.split.first.to_s,
            'name' => oc.customer_name.to_s
          }
        },
        'prepaid' => { 'total' => "#{prepaid_total}₹" },
        'payment' => { 'link' => "https://cutt.ly/#{payment_link}" }
      }

      # Templates built in the template manager carry a variable_mapping —
      # resolve through it so merchants can order/select variables freely.
      # Templates from the legacy flow have no mapping and keep the fixed
      # 4-positional contract documented above.
      body_parameters =
        if template.variable_mapping.present?
          ::Whatsapp::VariableResolver.call(template: template, payload: resolver_payload)
        else
          [
            { "type" => "text", "text" => @shop.owner_name.to_s },
            { "type" => "text", "text" => oc.final_order_number.to_s },
            { "type" => "text", "text" => "#{oc.order_amount}₹" },
            { "type" => "text", "text" => "#{prepaid_total}₹" }
          ]
        end

      # Media-header templates (IMAGE/VIDEO/DOCUMENT) require a header parameter
      # at send time. Omitting it makes Meta reject the ENTIRE send with #132012
      # ("Parameter format does not match format in the created template") — this
      # was why COD→prepaid BSP sends silently failed for image-header templates.
      # Resolve it exactly as Whatsapp::DispatchEventJob does; media_header_param
      # returns nil for text-only headers, so plain templates are unaffected.
      media_param = template.media_header_param(resolver_payload, @shop)
      header_parameters = media_param ? [media_param] : nil

      log = ::Meta::SendTemplateMessageService.call(
        account: account,
        template: template,
        recipient: oc.customer_number,
        body_parameters: body_parameters,
        header_parameters: header_parameters,
        button_slug: payment_link,
        event_type_key: "cod_to_prepaid",
        payload_snapshot: { "order_confirmation_id" => oc.id, "reminder_id" => (@reminder && @reminder["id"]) },
        source_external_id: "codprepaid:#{oc.id}:#{send_slug}"
      )
      write_log(oc, log&.meta_message_id, log ? "SUCCESS" : "DEDUP")
      log
    rescue ::Meta::SendTemplateMessageService::Error => e
      Rails.logger.error("[WhatsappPrepaidBspService] send failed oc=#{@order_confirmation&.id}: #{e.message}")
      write_log(@order_confirmation, nil, e.message.to_s)
      nil
    end

    private

    # Distinguishes the reminders scheduled for one order. A shared slug would
    # trip the partial unique index on whatsapp_message_logs and silently drop
    # every send after the first.
    def send_slug
      @send_key.presence || (@reminder && @reminder["id"]).presence || "default"
    end

    def write_log(oc, sid, status)
      return if oc.blank?

      TwilioLog.create(
        sid: sid,
        ver_type: "WHATSAPP_COD_PREPAID",
        country_code: oc.country_code,
        customer_number: oc.customer_number,
        status: status,
        order_confirmation: oc,
        shop: @shop
      )
    end
  end
end
