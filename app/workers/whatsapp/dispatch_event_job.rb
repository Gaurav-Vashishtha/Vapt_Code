module Whatsapp
  # Top-level fan-out for a Shopify event → WhatsApp message.
  # 1. Find the shop and its active binding for this event type (if any)
  # 2. Resolve recipient phone from the payload
  # 3. Resolve variables via VariableResolver
  # 4. Enqueue SendTemplateMessageJob
  class DispatchEventJob < ApplicationJob
    sidekiq_options queue: 'default', retry: false

    # Candidate paths within the payload to find the recipient phone, per event,
    # tried in order — the first non-blank wins. Shopify order webhooks often
    # leave `customer.phone` null and carry the contact number at the top-level
    # `order.phone` or in the shipping/billing address, so we fall back through
    # all of them instead of skipping silently.
    RECIPIENT_PATHS = {
      'order_created'         => [%w[order customer phone], %w[order phone], %w[order shipping_address phone], %w[order billing_address phone]],
      'order_created_partial' => [%w[order customer phone], %w[order phone], %w[order shipping_address phone], %w[order billing_address phone]],
      'cod_verification'    => [%w[order customer phone], %w[order phone], %w[order shipping_address phone], %w[order billing_address phone]],
      'order_fulfilled'     => [%w[order customer phone], %w[order phone], %w[order shipping_address phone], %w[order billing_address phone]],
      'first_time_purchase' => [%w[order customer phone], %w[order phone], %w[order shipping_address phone], %w[order billing_address phone]],
      'cod_to_prepaid'      => [%w[order customer phone], %w[order phone], %w[order shipping_address phone], %w[order billing_address phone]],
      'abandoned_cart'      => [%w[checkout customer phone], %w[checkout phone], %w[checkout shipping_address phone], %w[checkout billing_address phone]],
      'cart_abandoned'      => [%w[cart customer phone], %w[cart phone], %w[cart shipping_address phone]],
      'browse_abandoned'    => [%w[browse customer phone], %w[browse phone], %w[browse shipping_address phone]],
      'campaign_broadcast'  => [%w[customer phone]]
    }.merge(
      (EventRegistry::ORDER_EVENT_KEYS - %w[order_created order_created_partial cod_verification order_fulfilled first_time_purchase cod_to_prepaid])
        .index_with { [%w[order customer phone], %w[order phone], %w[order shipping_address phone], %w[order billing_address phone]] }
    ).freeze

    # Parallel ISO country-code paths used to repair phone numbers Shopify
    # delivers without a dial-code prefix (e.g. "7003393597" instead of
    # "+917003393597"). Meta rejects bare local numbers as INVALID_RECIPIENT —
    # we use Phonelib to stitch the dial code on when we can find one in the
    # same payload.
    COUNTRY_CODE_PATHS = {
      'order_created'         => [%w[order shipping_address country_code], %w[order billing_address country_code], %w[order customer default_address country_code]],
      'order_created_partial' => [%w[order shipping_address country_code], %w[order billing_address country_code], %w[order customer default_address country_code]],
      'cod_verification'    => [%w[order shipping_address country_code], %w[order billing_address country_code], %w[order customer default_address country_code]],
      'order_fulfilled'     => [%w[order shipping_address country_code], %w[order billing_address country_code], %w[order customer default_address country_code]],
      'first_time_purchase' => [%w[order shipping_address country_code], %w[order billing_address country_code], %w[order customer default_address country_code]],
      'cod_to_prepaid'      => [%w[order shipping_address country_code], %w[order billing_address country_code], %w[order customer default_address country_code]],
      'abandoned_cart'      => [%w[checkout shipping_address country_code], %w[checkout billing_address country_code], %w[checkout customer default_address country_code]],
      'cart_abandoned'      => [%w[cart shipping_address country_code]],
      'browse_abandoned'    => [%w[browse shipping_address country_code]],
      'campaign_broadcast'  => [%w[customer default_address country_code]]
    }.merge(
      (EventRegistry::ORDER_EVENT_KEYS - %w[order_created order_created_partial cod_verification order_fulfilled first_time_purchase cod_to_prepaid])
        .index_with { [%w[order shipping_address country_code], %w[order billing_address country_code], %w[order customer default_address country_code]] }
    ).freeze

    DISPATCH_FOLLOW_UPS = { 'cod_verification' => %w[cod_verification_reminder] }.freeze
    REFETCH_ORDER_KEY = '_refetch_order'.freeze
    SLIM_PAYLOAD_AFTER_MINUTES = 360
    PER_SHIPMENT_EVENTS = %w[order_out_for_delivery order_delivered].freeze

    # `inline:` (the 4th positional arg, default false) runs the downstream
    # SendTemplateMessageJob synchronously so the caller (the test endpoint)
    # gets back the resulting WhatsappMessageLog without a Sidekiq round-trip.
    # The default keeps every existing Sidekiq-enqueued call site unchanged.
    #
    # `recipient_override` (5th positional arg) lets the test endpoint
    # redirect the send to a specific phone number without having to mutate
    # the payload. Skips the RECIPIENT_PATHS lookup entirely when present.
    #
    # `stage_index` (6th positional arg, default 0) selects which binding to
    # use for staged events (abandoned_cart). Non-staged events leave it at 0.
    #
    # `delayed` (7th positional arg, default false) marks a run that has already
    # served the binding's configured `offset_minutes` wait. The first run of a
    # delay-eligible event re-enqueues itself with `perform_in(offset.minutes,
    # ..., delayed: true)` and returns; the delayed run then actually sends.
    # This centralises the per-notification delay so every dispatch source
    # (order webhooks, OTP branch, etc.) honours it without each caller having
    # to schedule. abandoned_cart is excluded because its own scheduler already
    # times each stage from the abandonment moment.
    DELAY_EXCLUDED_EVENTS = %w[abandoned_cart].freeze

    PARTIAL_EDIT_WAIT = 30.seconds
    PARTIAL_EDIT_MAX_ATTEMPTS = 10
    PARTIAL_EDIT_ATTEMPTS_KEY = '_partial_edit_attempts'.freeze

    def perform(event_type_key, shop_id_or_domain, payload, inline = false, recipient_override = nil, stage_index = 0, delayed = false)
      shop = resolve_shop(shop_id_or_domain)
      return Rails.logger.info("[whatsapp/dispatch] no shop for #{shop_id_or_domain}") unless shop

      payload_hash = payload.respond_to?(:to_h) ? payload.to_h : (payload || {})
      payload_hash = payload_hash.deep_stringify_keys if payload_hash.is_a?(Hash)
      partial_edit_attempts = payload_hash.is_a?(Hash) ? payload_hash.delete(PARTIAL_EDIT_ATTEMPTS_KEY).to_i : 0

      # `order_created` has an optional sibling event, `order_created_partial`,
      # reserved for orders placed as a partial payment. When the shop has
      # bound a template to it AND this particular order is actually a
      # partial-payment order, route there instead of the normal
      # order_created template — this is what lets a shop run two distinct
      # confirmation messages (one for partial-paid orders, one for the
      # rest). Any other event, or a shop that hasn't bound
      # order_created_partial, is unaffected and keeps today's behaviour.
      dispatch_event_type_key = event_type_key
      if event_type_key.to_s == 'order_created' && partial_payment_order?(payload_hash, shop)
        if shop.whatsapp_template_bindings.exists?(event_type_key: 'order_created_partial', stage_index: stage_index.to_i)
          dispatch_event_type_key = 'order_created_partial'
        end
      end

      binding = shop.whatsapp_template_bindings.find_by(
        event_type_key: dispatch_event_type_key,
        stage_index: stage_index.to_i
      )
      return Rails.logger.info("[whatsapp/dispatch] shop=#{shop.id} no binding for #{dispatch_event_type_key} stage=#{stage_index}") unless binding
      # Test sends (inline) still go out so merchants can preview a paused notification.
      if binding.paused? && !inline
        return Rails.logger.info("[whatsapp/dispatch] shop=#{shop.id} event=#{dispatch_event_type_key} stage=#{stage_index} paused")
      end

      # Route to the number bound to this event; fall back to the shop default
      # for legacy bindings that predate per-event routing.
      account = binding.whatsapp_account || shop.default_whatsapp_account
      return Rails.logger.info("[whatsapp/dispatch] shop=#{shop.id} event=#{dispatch_event_type_key} no sendable whatsapp number") unless account&.ready_to_send?

      template = binding.whatsapp_template
      return Rails.logger.warn("[whatsapp/dispatch] binding=#{binding.id} template missing or not approved") unless template&.approved?

      # Per-notification delay: wait the binding's offset_minutes before sending.
      # Re-enqueue once (delayed: true) so the actual send — including the dedup
      # check — happens after the wait. Inline (test) sends never delay so the
      # test endpoint gets an immediate result.
      offset_minutes = binding.offset_minutes.to_i
      offset_minutes = EventRegistry.default_offset_minutes(dispatch_event_type_key) unless offset_minutes.positive?
      if !inline && !delayed && offset_minutes.positive? && !DELAY_EXCLUDED_EVENTS.include?(dispatch_event_type_key.to_s)
        self.class.perform_in(
          offset_minutes.minutes,
          event_type_key, shop_id_or_domain, delayed_payload(payload_hash, dispatch_event_type_key, offset_minutes),
          inline, recipient_override, stage_index.to_i, true
        )
        return Rails.logger.info("[whatsapp/dispatch] shop=#{shop.id} event=#{dispatch_event_type_key} delayed #{offset_minutes}m")
      end

      # Inject shop context so templates can reference `store.name` etc. without
      # the caller having to supply it. Per-shop, never per-order. `owner_name`
      # holds the Shopify store display name (ShopifyAPI::Shop.current.name,
      # synced on app load) — the domain is only a fallback for shops that
      # haven't completed that sync yet.
      if payload_hash.is_a?(Hash) && payload_hash.delete(REFETCH_ORDER_KEY)
        live = fetch_live_order(shop, payload_hash.dig('order', 'id'))
        return Rails.logger.info("[whatsapp/dispatch] shop=#{shop.id} event=#{dispatch_event_type_key} order gone before delayed send") unless live

        payload_hash['order'] = live
      end

      payload_hash['shop'] ||= {
        'name'   => (shop.owner_name.presence || shop.shopify_domain),
        'domain' => shop.shopify_domain
      }
      payload_hash['shop']['url'] ||= "https://#{payload_hash['shop']['domain'].presence || shop.shopify_domain}" if payload_hash['shop'].is_a?(Hash)

      unless inline
        skip_reason = DispatchRelevance.skip_reason(dispatch_event_type_key, shop, payload_hash)
        if skip_reason
          return Rails.logger.info("[whatsapp/dispatch] shop=#{shop.id} event=#{dispatch_event_type_key} skipped: #{skip_reason}")
        end
      end

      # Resolve and inject a discount for staged events that carry one. The
      # resolver creates Shopify PriceRules for `auto` mode and caches the
      # generated code on the AbandonedCart row so retries are stable.
      inject_discount_into_payload(payload_hash, binding, shop) if discount_eligible?(dispatch_event_type_key)

      # Partial-payment orders: expose paid-online / remaining-on-delivery / total
      # as partial.* variables on order_created / order_created_partial (mirrors
      # the legacy MSG91 flow).
      if %w[order_created order_created_partial].include?(dispatch_event_type_key.to_s)
        if !inline && refresh_same_order_partial!(payload_hash, shop) == :edit_pending
          if partial_edit_attempts < PARTIAL_EDIT_MAX_ATTEMPTS
            retry_payload = payload_hash.merge(PARTIAL_EDIT_ATTEMPTS_KEY => partial_edit_attempts + 1)
            self.class.perform_in(
              PARTIAL_EDIT_WAIT,
              event_type_key, shop_id_or_domain, retry_payload, inline, recipient_override, stage_index.to_i, true
            )
            return Rails.logger.info("[whatsapp/dispatch] shop=#{shop.id} order=#{payload_hash.dig('order', 'id')} partial order edit pending; retry #{partial_edit_attempts + 1}")
          end

          SlackNotifyJob.perform_async(
            ":warning: (#{Rails.env}) order_created sent for SAME_ORDER partial order=#{payload_hash.dig('order', 'id')} " \
            "shop=#{shop.shopify_domain} with nothing outstanding — the partial order edit never completed"
          )
        end
        inject_partial_into_payload(payload_hash, shop)
      end

      recipient = recipient_override.presence || recipient_from(dispatch_event_type_key, payload_hash)
      return Rails.logger.info("[whatsapp/dispatch] shop=#{shop.id} event=#{dispatch_event_type_key} no recipient phone in payload") if recipient.blank?

      source_external_id = source_external_id_from(dispatch_event_type_key, payload_hash)
      body_parameters = VariableResolver.call(template: template, payload: payload_hash)
      tracking = inline ? nil : {
        shop_id: shop.id, event_type_key: dispatch_event_type_key.to_s, source_external_id: source_external_id,
        stage_index: stage_index.to_i, recipient: recipient
      }
      button_slug = UrlButtonResolver.call(template: template, payload: payload_hash, tracking: tracking)
      # Test sends usually run on sample data whose URL Cutt.ly can't shorten,
      # so the slug comes back blank — which would drop the button parameter and
      # trigger Meta 131008 ("Required parameter is missing"). Substitute a
      # placeholder so the test still delivers. Production (non-inline) keeps the
      # strict behaviour: a real recovery URL resolves to a real slug.
      if button_slug.blank? && inline && template_has_dynamic_url_button?(template)
        button_slug = 'preview'
      end
      header_parameters = resolve_header_parameters(template, payload_hash, shop)

      # Dedup against a prior send for the same (shop, event, source, stage).
      # Two fan-out sites can converge on the same dispatch — e.g. an order
      # webhook handled by both SqsOrderCreateConsumerJob and the legacy
      # OrderConfirmationCreateJob → without this, the same order produces
      # two cod_verification sends. Inline test sends skip dedup so the test
      # endpoint still works.
      if !inline && source_external_id.present?
        already = WhatsappMessageLog.already_sent_for_stage(
          shop_id: shop.id,
          event_type_key: dispatch_event_type_key.to_s,
          source_external_id: source_external_id,
          stage_index: stage_index.to_i
        ).where.not(status: :failed).exists?
        if already
          Rails.logger.info(
            "[whatsapp/dispatch] dedup blocked shop=#{shop.id} event=#{dispatch_event_type_key} " \
            "source=#{source_external_id} stage=#{stage_index} — already sent"
          )
          # Slack visibility for codkingdemo while we're verifying the fix.
          # Remove this block once the dedup flow is trusted.
          if shop.shopify_domain == 'codkingdemo.myshopify.com'
            SlackNotifyJob.perform_async(
              ":repeat: DispatchEventJob dedup blocked (#{Rails.env}) " \
              "shop=#{shop.shopify_domain} event=#{dispatch_event_type_key} " \
              "source=#{source_external_id} stage=#{stage_index}"
            )
          end
          return
        end
      end

      # Inline test sends bypass dedup at the DB level: null source_external_id
      # → the partial unique index (which has `WHERE source_external_id IS NOT
      # NULL`) doesn't apply → repeated tests against the same sample order
      # always create a fresh log row. Production sends keep source_external_id
      # so dedup + recovery tracking work normally.
      log_source_external_id = inline ? nil : source_external_id

      args = [
        account.id, template.id, recipient,
        body_parameters, header_parameters,
        dispatch_event_type_key, payload_hash, button_slug,
        # Trailing positional args for dedup metadata. SendTemplateMessageJob
        # forwards them to SendTemplateMessageService.
        stage_index.to_i, log_source_external_id
      ]

      if inline
        SendTemplateMessageJob.new.perform(*args)
      else
        SendTemplateMessageJob.perform_async(*args)
        schedule_follow_ups(dispatch_event_type_key, shop_id_or_domain, payload) if stage_index.to_i.zero?
      end
    end

    # Real-send header parameters for media templates. Logs (but does not
    # block) when the template needs a media param and none is stored — Meta
    # will return 132012 in that case and the failure will surface on the
    # WhatsappMessageLog row.
    def resolve_header_parameters(template, payload = nil, shop = nil)
      media_param = template.media_header_param(payload, shop)
      return [media_param] if media_param

      header = Array(template.components).find { |c| c.is_a?(Hash) && c['type'].to_s.casecmp?('HEADER') }
      if header && %w[IMAGE VIDEO DOCUMENT].include?(header['format'].to_s.upcase)
        Rails.logger.warn("[whatsapp/dispatch] template=#{template.id} has #{header['format']} header but no resolvable media — Meta will reject the send. Update template.header_media with a media_id or url.")
      end
      nil
    end

    private

    # Long waits (feedback, reorder) would otherwise park the whole order JSON in
    # Redis for weeks; keep only the id and re-read the order when the job runs.
    def delayed_payload(payload_hash, event_type_key, offset_minutes)
      order_id = payload_hash.is_a?(Hash) ? payload_hash.dig('order', 'id') : nil
      return payload_hash unless order_id.present? && offset_minutes >= SLIM_PAYLOAD_AFTER_MINUTES &&
                                 EventRegistry::ORDER_EVENT_KEYS.include?(event_type_key.to_s)

      payload_hash.slice('fulfillment', 'delivery').merge('order' => { 'id' => order_id }, REFETCH_ORDER_KEY => true)
    end

    def schedule_follow_ups(event_type_key, shop_id_or_domain, payload)
      Array(DISPATCH_FOLLOW_UPS[event_type_key.to_s]).each do |follow_up|
        self.class.perform_async(follow_up, shop_id_or_domain, payload)
      end
    end

    # True if the template's BUTTONS component has a URL button whose URL
    # contains a {{N}} placeholder — Meta then requires a button parameter at
    # send time. Detected from the components (what Meta approved), not the
    # url_button config, so it catches templates synced/created without that
    # config (which would otherwise hit 131008 with no fallback).
    def template_has_dynamic_url_button?(template)
      return true if template.url_button_present?

      buttons = Array(template.components).find do |c|
        c.is_a?(Hash) && c['type'].to_s.casecmp?('BUTTONS')
      end
      Array(buttons && buttons['buttons']).any? do |b|
        next false unless b.is_a?(Hash) && b['type'].to_s.casecmp?('URL')
        b['url'].to_s.include?('{{')
      end
    end

    def resolve_shop(id_or_domain)
      return Shop.find_by(id: id_or_domain) if id_or_domain.is_a?(Integer)
      Shop.find_by(shopify_domain: id_or_domain.to_s)
    end

    def recipient_from(event_type_key, payload)
      paths = RECIPIENT_PATHS[event_type_key]
      return nil unless paths

      raw_phone = nil
      paths.each do |path|
        value = path.reduce(payload) { |acc, k| acc.is_a?(Hash) ? acc[k] : nil }
        next if value.blank?
        raw_phone = value
        break
      end
      return nil if raw_phone.nil?

      country_iso = country_iso_from(event_type_key, payload)
      normalize_recipient_phone(raw_phone, country_iso)
    end

    # Returns the ISO-3166 country code (e.g. "IN") from the payload, or nil
    # if no address-bearing block was found.
    def country_iso_from(event_type_key, payload)
      paths = COUNTRY_CODE_PATHS[event_type_key]
      return nil unless paths
      paths.each do |path|
        value = path.reduce(payload) { |acc, k| acc.is_a?(Hash) ? acc[k] : nil }
        return value.to_s if value.present?
      end
      nil
    end

    # Convert raw payload phone into the digits-only E.164-ish form Meta wants.
    # Three cases:
    #   1. Already starts with "+" (E.164 from a checkout extension or similar)
    #      → strip "+" and non-digits, return.
    #   2. Bare local number + we have an ISO country hint
    #      → Phonelib stitches the dial code on (`+91` + `7003393597`).
    #   3. Already digits-only and starts with a plausible dial code (length
    #      heuristic) → return as-is. Belt-and-suspenders for callers that
    #      send well-formed numbers without a "+".
    def normalize_recipient_phone(raw_phone, country_iso)
      digits = raw_phone.to_s.gsub(/\D/, '').sub(/\A0+/, '')
      return nil if digits.blank?

      # If the raw value already had an explicit "+" prefix, trust it.
      return digits if raw_phone.to_s.strip.start_with?('+')

      if country_iso.present?
        parsed = Phonelib.parse(digits, country_iso)
        if parsed.valid?
          return parsed.e164.to_s.gsub(/\D/, '')
        end

        # Phonelib couldn't validate (typo, wrong country hint) — fall back to
        # explicit dial-code prefixing so we at least produce a Meta-acceptable
        # candidate rather than silently failing.
        dial = Phonelib.phone_data.dig(country_iso.to_s.upcase, :country_code)
        return "#{dial}#{digits}" if dial.present? && !digits.start_with?(dial)
      end

      # No country hint + no "+" prefix. Best effort: return what we have.
      # Meta will reject it, but the error_message on the resulting log row
      # will make the cause clear.
      digits
    end

    # Stable external id we can dedup against. Used by the abandoned-cart
    # cron scheduler so a re-run of the same window doesn't enqueue a fresh
    # send for stages we already covered.
    def source_external_id_from(event_type_key, payload)
      case event_type_key.to_s
      when 'abandoned_cart'
        (payload.dig('checkout', 'token') || payload.dig('checkout', 'id')).to_s.presence
      when 'cart_abandoned'
        (payload.dig('cart', 'token') || payload.dig('cart', 'id')).to_s.presence
      when 'browse_abandoned'
        (payload.dig('browse', 'token') || payload.dig('browse', 'id')).to_s.presence
      when *PER_SHIPMENT_EVENTS
        order_id = (payload.dig('order', 'id') || payload.dig('order', 'name')).to_s.presence
        fulfillment_id = payload.dig('fulfillment', 'id').to_s.presence
        order_id && [order_id, fulfillment_id].compact.join(':')
      when *EventRegistry::ORDER_EVENT_KEYS
        (payload.dig('order', 'id') || payload.dig('order', 'name')).to_s.presence
      end
    end

    # Only events that participate in the discount-resolver workflow get a
    # `discount.*` blob injected. Other events are left untouched even if the
    # binding accidentally carries a non-blank discount_config.
    def discount_eligible?(event_type_key)
      %w[abandoned_cart cart_abandoned].include?(event_type_key.to_s)
    end

    # Build an AbandonedCart-lookalike (or look up the real row) so the
    # resolver can cache the generated code per (cart, stage). The cart's
    # token is the stable identifier we key off.
    def inject_discount_into_payload(payload_hash, binding, shop)
      return if binding.discount_config.blank? || binding.discount_config['mode'].to_s == 'none'

      # Defense-in-depth (the bind-time guard normally prevents this): if the
      # bound template maps no discount.* variable, the resolved code can't reach
      # the customer — and for `auto` mode DiscountResolver would create an
      # unredeemable Shopify price rule on every send. Skip resolution entirely.
      mapping = binding.whatsapp_template&.variable_mapping || {}
      unless mapping.values.any? { |v| v.to_s.start_with?('discount.') }
        Rails.logger.warn("[whatsapp/dispatch] binding=#{binding.id} has discount_config but template maps no discount.* variable — skipping discount")
        return
      end

      checkout_token = (payload_hash.dig('checkout', 'token') || payload_hash.dig('cart', 'token')).to_s.presence
      checkout_id    = (payload_hash.dig('checkout', 'id') || payload_hash.dig('cart', 'id')).to_s.presence
      cart = shop.abandoned_carts.find_by(checkout_id: (checkout_token || checkout_id)) if shop.respond_to?(:abandoned_carts)

      result = DiscountResolver.call(
        shop: shop,
        abandoned_cart: cart,
        discount_config: binding.discount_config,
        stage_index: binding.stage_index
      )
      return unless result

      payload_hash['discount'] = result.to_payload_hash
    end

    # Inject partial-payment amounts (paid online / remaining on delivery / total)
    # for partial-payment orders, formatted with the order's currency symbol, so
    # order_created / order_created_partial templates can show them. Mirrors the
    # legacy MSG91 WhatsappConfirmationService formula. No-op for non-partial
    # orders, leaving the partial.* variables blank.
    def inject_partial_into_payload(payload_hash, shop)
      order = payload_hash['order']
      return unless order.is_a?(Hash)
      return unless partial_payment_order?(payload_hash, shop)

      if shop.setting&.partial_payment_flow == 'SAME_ORDER'
        total     = order['current_total_price'].to_f
        remaining = order['total_outstanding'].to_f
      else
        total     = order['current_total_price'].to_f + order['current_total_discounts'].to_f
        remaining = order['current_total_price'].to_f
      end
      paid = [total - remaining, 0].max

      symbol = currency_symbol_for(order['currency'])
      payload_hash['partial'] = {
        'total'     => format_money(symbol, total),
        'paid'      => format_money(symbol, paid),
        'remaining' => format_money(symbol, remaining)
      }
    end

    # A SAME_ORDER partial order is created holding only the advance-payment
    # line item, already paid, so the orders/create payload shows nothing
    # outstanding. PartialOrderEditJob swaps in the real products afterwards;
    # the message has to be built from the order as it is after that edit.
    def refresh_same_order_partial!(payload_hash, shop)
      return nil unless shop.setting&.partial_payment_flow == 'SAME_ORDER'
      return nil unless partial_payment_order?(payload_hash, shop)

      live = fetch_live_order(shop, payload_hash.dig('order', 'id'))
      return nil unless live

      payload_hash['order'] = payload_hash['order'].merge(live)
      live['total_outstanding'].to_f.positive? ? :edited : :edit_pending
    end

    def fetch_live_order(shop, order_id)
      return nil if order_id.blank?

      shop.init_session
      hash = JSON.parse(ShopifyAPI::Order.find(order_id).to_json)
      hash = hash['order'] if hash.is_a?(Hash) && hash.key?('order') && hash.size == 1
      hash.is_a?(Hash) && hash['id'].present? ? hash : nil
    rescue StandardError => e
      Rails.logger.warn("[whatsapp/dispatch] live order fetch failed shop=#{shop.id} order=#{order_id}: #{e.class}: #{e.message}")
      nil
    end

    # True when this order payload represents a partial-payment order, per the
    # shop's configured partial-payment flow (SAME_ORDER vs a separate advance
    # order). Shared by inject_partial_into_payload and the order_created →
    # order_created_partial routing check in #perform.
    def partial_payment_order?(payload_hash, shop)
      order = payload_hash.is_a?(Hash) ? payload_hash['order'] : nil
      return false unless order.is_a?(Hash)

      if shop.setting&.partial_payment_flow == 'SAME_ORDER'
        partial_same_order?(order)
      else
        partial_new_order?(order)
      end
    end

    # SAME_ORDER partial: marked via the partial_payment_variants note attribute.
    def partial_same_order?(order)
      Array(order['note_attributes']).any? do |na|
        na.is_a?(Hash) && na['name'].to_s == 'partial_payment_variants'
      end
    end

    # New-order partial flow: the advance is a separate order whose note carries
    # this marker.
    def partial_new_order?(order)
      order['note'].to_s.include?('partial order created')
    end

    def currency_symbol_for(currency)
      (CurrencyHelper.symbol_for(currency) if defined?(CurrencyHelper)) || currency.to_s
    rescue StandardError
      currency.to_s
    end

    def format_money(symbol, amount)
      amount = amount.to_f
      num = amount == amount.round ? amount.round.to_s : format('%.2f', amount)
      "#{symbol}#{num}"
    end
  end
end
