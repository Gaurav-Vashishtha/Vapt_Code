module Api
  module Whatsapp
    # Lets merchants test an active automation against a real Shopify order or
    # checkout from the Automations page. Mirrors what SqsConsumerJob does for
    # a webhook arrival, then runs Whatsapp::DispatchEventJob inline so we can
    # return the resulting WhatsappMessageLog row immediately.
    class AutomationTestsController < AuthenticatedController
      SUPPORTED_EVENTS = %w[order_created cod_verification order_fulfilled first_time_purchase abandoned_cart pre_order_otp cod_to_prepaid
                            cod_verification_reminder order_cancelled order_out_for_delivery order_delivered feedback_request reorder_reminder].freeze

      def create
        event_type_key = params[:event_type_key].to_s

        unless SUPPORTED_EVENTS.include?(event_type_key)
          return render(json: { error: "Event type '#{event_type_key}' is not testable" }, status: :unprocessable_entity)
        end

        # Staged events (abandoned_cart) have one binding per stage_index; the
        # rest only have stage 0.
        stage_index = params[:stage_index].to_i
        binding = @shop.whatsapp_template_bindings.find_by(
          event_type_key: event_type_key,
          stage_index: stage_index
        )
        unless binding
          return render(json: { error: "No active automation for '#{event_type_key}' (reminder #{stage_index + 1}). Turn one on first." }, status: :unprocessable_entity)
        end

        recipient_override = normalize_recipient(params[:recipient_override])

        # pre_order_otp is an authentication template driven by a literal code,
        # not a Shopify payload. Test it by sending an arbitrary 4-digit code
        # via the exact path production uses (PreOrderOtpBspService →
        # SendTemplateMessageService) so the body param AND the copy-code button
        # param match a real OTP send.
        return send_pre_order_otp_test(binding, recipient_override) if event_type_key == 'pre_order_otp'

        # Synthetic mode (no Shopify lookup) needs a phone number to send to —
        # the synthesized payload doesn't carry a real customer phone.
        if params[:order_id].blank? && recipient_override.blank?
          return render(
            json: { error: "Either a Shopify order ID or a 'Send to' phone number is required." },
            status: :unprocessable_entity
          )
        end

        begin
          payload = build_payload(event_type_key, params[:order_id])
        rescue ::ActiveResource::ResourceNotFound
          return render(json: { error: "Couldn't find that order/checkout on Shopify." }, status: :not_found)
        rescue ArgumentError => e
          return render(json: { error: e.message }, status: :unprocessable_entity)
        rescue => e
          Rails.logger.warn("[automation_tests] payload build failed shop=#{@shop.id} event=#{event_type_key}: #{e.class}: #{e.message}")
          return render(json: { error: "Couldn't build the test message (#{e.class}: #{e.message})." }, status: :unprocessable_entity)
        end

        # Snapshot before dispatch so we can find the row created by this test.
        before_id = @shop.whatsapp_message_logs.maximum(:id).to_i

        begin
          ::Whatsapp::DispatchEventJob.new.perform(
            event_type_key,
            @shop.shopify_domain,
            payload,
            true,                # inline — run SendTemplateMessageJob synchronously
            recipient_override,
            stage_index          # pick the binding for the stage under test
          )
        rescue => e
          # Surface the real failure honestly rather than a 500 or a misleading
          # "couldn't fetch the order" — this is the send/dispatch step.
          Rails.logger.error("[automation_tests] dispatch failed shop=#{@shop.id} event=#{event_type_key} stage=#{stage_index}: #{e.class}: #{e.message}")
          return render(json: { error: "Send failed: #{e.message}" }, status: :unprocessable_entity)
        end

        # If the dispatcher early-exited (no recipient, template not approved,
        # etc.), no log row is created. Surface the most useful reason we can
        # derive client-side; full diagnostic is in the Sidekiq log.
        log = @shop.whatsapp_message_logs.where('id > ?', before_id).order(id: :desc).first
        unless log
          return render(json: {
            error: dispatch_skip_reason(event_type_key, payload, recipient_override, binding)
          }, status: :unprocessable_entity)
        end

        render json: {
          ok: log.status != 'failed',
          log_id: log.id,
          status: log.status,
          recipient: log.recipient,
          template_name: log.template_name,
          error_code: log.error_code,
          error_message: log.error_message
        }
      end

      private

      # Sends a one-off test OTP (arbitrary 4-digit code) through the same
      # SendTemplateMessageService call PreOrderOtpBspService uses in production:
      # the code is supplied as the body parameter and as the copy-code button
      # slug. No Shopify order is involved; the recipient must be provided.
      def send_pre_order_otp_test(binding, recipient_override)
        if recipient_override.blank?
          return render(json: { error: "A 'Send to' phone number is required to test the OTP message." }, status: :unprocessable_entity)
        end

        account = binding.whatsapp_account || @shop.default_whatsapp_account
        unless account&.ready_to_send?
          return render(json: { error: "Your WhatsApp account isn't fully verified yet. Check the Account page." }, status: :unprocessable_entity)
        end

        template = binding.whatsapp_template
        unless template&.approved?
          return render(json: { error: "The bound template isn't approved by WhatsApp yet." }, status: :unprocessable_entity)
        end

        otp = rand(1000..9999).to_s

        begin
          log = Meta::SendTemplateMessageService.call(
            account: account,
            template: template,
            recipient: recipient_override,
            body_parameters: [{ 'type' => 'text', 'text' => otp }],
            button_slug: otp,
            event_type_key: 'pre_order_otp',
            payload_snapshot: { 'otp' => true, 'source' => 'pre_order_otp', 'test' => true }
          )
        rescue Meta::SendTemplateMessageService::Error => e
          return render(json: { error: "Send failed: #{e.message}" }, status: :unprocessable_entity)
        end

        unless log
          return render(json: { error: "Couldn't send the test OTP — check Sidekiq logs (grep for [whatsapp/send])." }, status: :unprocessable_entity)
        end

        render json: {
          ok: log.status != 'failed',
          log_id: log.id,
          status: log.status,
          recipient: log.recipient,
          template_name: log.template_name,
          error_code: log.error_code,
          error_message: log.error_message
        }
      end

      def normalize_recipient(value)
        return nil if value.blank?
        # Strip whitespace; Meta wants digits-only at send time, but the
        # dispatcher's normalize_phone handles that downstream.
        value.to_s.strip
      end

      # Events that always test against registry samples — no real Shopify
      # source is offered for them in the UI (abandoned carts are ephemeral;
      # an arbitrary order isn't a genuine "first" purchase).
      SYNTHETIC_ONLY_EVENTS = %w[abandoned_cart first_time_purchase].freeze

      def build_payload(event_type_key, source_id)
        # Sample payload from the event's registry values — always the base, so
        # every variable renders something even when the real order is sparse.
        samples = synthesize_payload(event_type_key)
        return samples if source_id.blank? || SYNTHETIC_ONLY_EVENTS.include?(event_type_key)

        real = fetch_real_payload(event_type_key, source_id)
        # Real data wins; samples fill any gaps. So a fulfilment test on an
        # unfulfilled order (no tracking) still renders sample tracking values
        # instead of the "—" blank fallback.
        samples.deep_merge(real)
      end

      def fetch_real_payload(event_type_key, source_id)
        @shop.init_session

        # Shopify order IDs are numeric. Pull the digits out so a pasted
        # "#1023", a GID, or stray whitespace doesn't reach the gem and surface
        # as a cryptic "string not matched" error. Empty → clean message.
        numeric_id = source_id.to_s[/\d+/]
        raise ArgumentError, "Enter a numeric Shopify order ID (got #{source_id.inspect})." if numeric_id.blank?

        case event_type_key
        when 'order_created', 'cod_verification', 'cod_verification_reminder', 'order_cancelled', 'feedback_request', 'reorder_reminder'
          order = ::ShopifyAPI::Order.find(numeric_id)
          { 'order' => JSON.parse(order.to_json).to_h }

        when 'order_fulfilled', 'order_out_for_delivery', 'order_delivered'
          order = ::ShopifyAPI::Order.find(numeric_id)
          order_hash = JSON.parse(order.to_json).to_h
          latest = Array(order_hash['fulfillments'])
                     .max_by { |f| f['updated_at'] || f['created_at'] || '' }
          # No fulfillments yet — return the order with an empty fulfillment so
          # the deep-merge keeps the sample tracking values for this test.
          latest ||= {}
          latest['order_name'] ||= order_hash['name']
          { 'order' => order_hash, 'fulfillment' => latest }

        when 'cod_to_prepaid'
          cod_to_prepaid_payload(numeric_id)
        else
          {}
        end
      end

      # cod_to_prepaid's registry paths (order.total, prepaid.total, ...) don't
      # line up with the raw Shopify order shape, so map the fields explicitly.
      # prepaid.total is only real when the order has an OrderConfirmation row
      # (the production flow's source); otherwise the sample fills the gap.
      def cod_to_prepaid_payload(numeric_id)
        order = ::ShopifyAPI::Order.find(numeric_id)
        oh = JSON.parse(order.to_json).to_h

        payload = {
          'shop' => { 'name' => (@shop.owner_name.presence || @shop.shopify_domain) },
          'order' => {
            'name' => oh['name'],
            'total' => ("#{oh['total_price']}₹" if oh['total_price'].present?),
            'phone' => oh['phone'],
            'customer' => {
              'first_name' => oh.dig('customer', 'first_name'),
              'name' => [oh.dig('customer', 'first_name'), oh.dig('customer', 'last_name')].compact.join(' ').presence,
              'phone' => oh.dig('customer', 'phone')
            }.compact,
            'shipping_address' => oh['shipping_address'].is_a?(Hash) ? oh['shipping_address'].slice('phone', 'country_code') : nil
          }.compact
        }

        oc = OrderConfirmation.find_by(shop_id: @shop.id, order_id: oh['id'].to_s)
        prepaid = prepaid_total_for(oc)
        payload['prepaid'] = { 'total' => prepaid } if prepaid
        payload
      end

      def prepaid_total_for(oc)
        return nil unless oc

        setting = @shop.setting
        total = ShopifyServices::PrepaidOrderService
                .new(nil, @shop, oc.id)
                .get_total_amount(
                  discount: setting&.prepaid_discount,
                  discount_type: setting&.prepaid_discount_type,
                  add_shipping: false
                ).to_i
        "#{total}₹"
      rescue => e
        Rails.logger.warn("[automation_tests] prepaid total failed oc=#{oc.id}: #{e.class}: #{e.message}")
        nil
      end

      # Build a payload that satisfies the event's variable paths using the
      # registry's `sample` values. Walks each variable's `path` (e.g.
      # `order.customer.first_name`) and seeds the nested hash with that
      # sample so VariableResolver renders identical output to a real send.
      def synthesize_payload(event_type_key)
        vars = ::Whatsapp::EventRegistry.variables_for(event_type_key)
        payload = {}
        vars.each do |v|
          next if v[:source] == :literal
          next unless v[:path]
          set_path(payload, v[:path], v[:sample])
        end
        payload
      end

      def set_path(hash, path, value)
        keys = path.to_s.split('.')
        last = keys.pop
        node = hash
        keys.each do |k|
          # Coerce non-hash intermediates to a hash so we can descend. Some
          # events declare both a parent path and a child of it (e.g.
          # `order.shipping_address` as a flat address string AND
          # `order.shipping_address.city`). Without this, descending into the
          # string sample raises "IndexError: string not matched".
          node[k] = {} unless node[k].is_a?(Hash)
          node = node[k]
        end
        # Don't clobber a nested hash that a more specific path already built —
        # the structured value (which VariableResolver can format) wins over a
        # flat sample string for the same key.
        node[last] = value unless node[last].is_a?(Hash)
      end

      # Best-effort explanation for "log row wasn't created". The dispatcher
      # logs the exact reason to Sidekiq but doesn't surface it as a return
      # value, so we re-check the most common preconditions here.
      def dispatch_skip_reason(event_type_key, payload, override, binding)
        account = binding.whatsapp_account || @shop.default_whatsapp_account
        unless account&.ready_to_send?
          return "Your WhatsApp account isn't fully verified yet. Check the Account page."
        end
        unless binding.whatsapp_template&.approved?
          return "The bound template isn't approved by WhatsApp yet."
        end
        if override.blank?
          recipient = ::Whatsapp::DispatchEventJob::RECIPIENT_PATHS[event_type_key]&.find do |path|
            v = path.reduce(payload) { |acc, k| acc.is_a?(Hash) ? acc[k] : nil }
            return nil if v.present?  # found a recipient — skip-reason is elsewhere
          end
          return "This order/checkout has no customer phone we can resolve. Provide a 'Send to' override to test."
        end
        "Couldn't dispatch — check Sidekiq logs (grep for [whatsapp/dispatch])."
      end
    end
  end
end
