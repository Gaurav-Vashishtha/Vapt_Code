# frozen_string_literal: true

module Webhooks
  class ProcessInboundEventJob < ApplicationJob
    sidekiq_options queue: 'administration', retry: 3

    MAX_SLACK_TEXT = 3500

    def perform(inbound_webhook_event_id)
      record = InboundWebhookEvent.find_by(id: inbound_webhook_event_id)
      return unless record

      endpoint = record.webhook_endpoint
      shop = record.shop
      return record.mark_skipped!('shop missing') if shop.blank?
      return record.mark_skipped!('endpoint missing') if endpoint.blank?

      mirror_to_slack(record) if endpoint.mirror_to_slack?

      event_name = record.event_name.to_s
      definition = ::Webhooks::SourceRegistry.event(endpoint.provider, event_name)
      if definition.nil?
        endpoint.record_skipped!
        return record.mark_skipped!("unknown event #{event_name.presence || '(none)'}")
      end

      role = definition[:role]
      if role == :ignore
        endpoint.record_skipped!
        return record.mark_skipped!('event role is ignore')
      end

      unless endpoint.event_enabled?(event_name)
        endpoint.record_skipped!
        return record.mark_skipped!('event disabled for this endpoint')
      end

      adapter = ::Webhooks::SourceRegistry.adapter_for(endpoint.provider)
      normalized = adapter.call(
        provider: endpoint.provider,
        event_name: event_name,
        payload: record.payload,
        shop: shop,
        endpoint: endpoint
      )

      result =
        case normalized.role
        when :suppress then handle_suppression(shop, normalized)
        when :trigger  then handle_trigger(shop, normalized)
        else :ignored
        end

      if result.is_a?(String)
        endpoint.record_skipped!
        record.mark_skipped!(result)
      else
        endpoint.record_processed!
        record.mark_processed!(internal_event_type_key: normalized.event_type_key)
      end
    rescue StandardError => e
      Rails.logger.error("[webhook/process] event=#{inbound_webhook_event_id} #{e.class}: #{e.message}")
      record&.webhook_endpoint&.record_failure!
      record&.mark_failed!(e)
      raise
    end

    private

    def handle_trigger(shop, normalized)
      return 'no recipient phone in payload' if normalized.phone.blank?
      return 'no recovery url could be resolved' if normalized.recovery_url.blank?

      # Out-of-order delivery is assumed: order_completed can land before the
      # abandonment event it recovers.
      if already_recovered?(shop, normalized)
        return 'cart already recovered'
      end

      # Every trigger gets an anchor row: DiscountResolver caches auto-generated
      # codes on it, the existing recovery paths flip its notes to 'Recovered',
      # and for abandoned_cart both schedulers read it as their third funnel.
      anchor = upsert_anchor(shop, normalized)
      return 'could not persist cart' if anchor.blank?

      return dispatch_abandoned_cart(shop, anchor, normalized) if normalized.event_type_key == 'abandoned_cart'

      dispatch_simple_event(shop, normalized)
    end

    def dispatch_abandoned_cart(shop, anchor, normalized)
      if shop.bsp_abandoned_cart?
        Rails.logger.info("[webhook/process] shop=#{shop.id} cart=#{anchor.checkout_id} queued for BSP scheduler")
      else
        schedule_legacy_stages(shop, anchor, normalized)
      end

      :ok
    end

    # cart_abandoned / browse_abandoned have no multi-source scheduler to feed,
    # and DispatchEventJob honours each binding's offset_minutes itself, so they
    # dispatch straight through.
    def dispatch_simple_event(shop, normalized)
      bindings = shop.whatsapp_template_bindings.for_event(normalized.event_type_key).ordered_by_stage.to_a
      return "no binding for #{normalized.event_type_key}" if bindings.empty?

      bindings = bindings.reject(&:paused?)
      return "#{normalized.event_type_key} paused" if bindings.empty?
      return 'no sendable whatsapp number' unless shop.whatsapp_account_for(normalized.event_type_key)&.ready_to_send?

      bindings.each do |binding|
        already = WhatsappMessageLog.already_sent_for_stage(
          shop_id: shop.id,
          event_type_key: normalized.event_type_key,
          source_external_id: normalized.source_external_id,
          stage_index: binding.stage_index
        ).exists?
        next if already

        ::Whatsapp::DispatchEventJob.perform_async(
          normalized.event_type_key,
          shop.shopify_domain,
          normalized.payload,
          false,
          nil,
          binding.stage_index
        )
      end

      :ok
    end

    def upsert_anchor(shop, normalized)
      anchor = shop.abandoned_carts.find_or_initialize_by(
        checkout_id: normalized.source_external_id,
        is_anchor: true
      )

      anchor.assign_attributes(
        source: source_for(normalized),
        url: normalized.recovery_url,
        phone: normalized.phone,
        country_code: normalized.country_code.to_s,
        notif_type: 'WHATSAPP',
        total_price: normalized.total_price.to_f,
        name: normalized.first_name.presence || 'Customer',
        featured_image: normalized.featured_image.to_s,
        shopify_created_at: normalized.occurred_at.to_s,
        source_payload: normalized.payload
      )
      anchor.save!
      anchor
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("[webhook/process] shop=#{shop.id} anchor save failed: #{e.message}")
      nil
    end

    # Mirrors NetworkJobs::AbandonedCartScheduleJob: one row per configured
    # offset, each with its own ShopifyJobs::AbandonedCartJob. Rows must be left
    # with a nil status — AbandonedCartJob treats IN_PROGRESS as already sent.
    def schedule_legacy_stages(shop, anchor, normalized)
      setting = shop.setting
      return if setting.blank?

      anchored_at = normalized.occurred_at || Time.current

      sms_offsets = parse_offsets(setting.ac_sms_schedule) if setting.abandoned_cart_enabled
      whatsapp_offsets = parse_offsets(setting.ac_whatsapp_schedule) if setting.ac_whatsapp

      schedule_stage_rows(shop, anchor, normalized, 'SMS', sms_offsets, anchored_at, setting)
      schedule_stage_rows(shop, anchor, normalized, 'WHATSAPP', whatsapp_offsets, anchored_at, setting)
    end

    def schedule_stage_rows(shop, anchor, normalized, notif_type, offsets, anchored_at, setting)
      Array(offsets).each_with_index do |offset, index|
        intended_time = anchored_at + offset.minutes
        next if intended_time < 30.minutes.ago

        exists = shop.abandoned_carts.where(
          checkout_id: anchor.checkout_id,
          notif_type: notif_type,
          scheduled_at: intended_time
        ).exists?
        next if exists

        row = shop.abandoned_carts.new(
          checkout_id: anchor.checkout_id,
          source: anchor.source,
          is_anchor: false,
          url: normalized.recovery_url,
          shopify_created_at: anchored_at.to_s,
          phone: normalized.phone,
          country_code: normalized.country_code.to_s,
          notif_type: notif_type,
          total_price: normalized.total_price.to_f,
          name: normalized.first_name.presence || 'Customer',
          scheduled_at: intended_time,
          featured_image: normalized.featured_image.to_s,
          source_payload: normalized.payload,
          dynamic_config: (notif_type == 'WHATSAPP' ? setting.abandoned_cart_configs&.[](index) : nil)
        )
        next unless row.save

        delay = [(intended_time - Time.current).to_i, 0].max
        begin
          ShopifyJobs::AbandonedCartJob.perform_in(delay.seconds, shop.id, row.id)
        rescue StandardError => e
          row.destroy
          Rails.logger.error("[webhook/process] shop=#{shop.id} failed to schedule #{notif_type}: #{e.message}")
        end
      end
    end

    def parse_offsets(raw)
      raw.to_s.split(',').map(&:strip).reject(&:blank?).map(&:to_i).select { |n| n >= 0 }
    end

    def handle_suppression(shop, normalized)
      references = Array(normalized.external_references).compact_blank
      return 'no references to suppress on' if references.empty? && normalized.phone.blank?

      carts = shop.abandoned_carts.where(checkout_id: references)
      carts = carts.or(shop.abandoned_carts.where(phone: normalized.phone)) if normalized.phone.present? && normalized.marks_recovered

      touched = 0
      carts.find_each do |cart|
        next if cart.recovered?

        if normalized.marks_recovered
          cart.update_columns(notes: 'Recovered', updated_at: Time.current)
        else
          # A non-recovery suppression only cancels the earlier-funnel nudges,
          # so the checkout-abandonment clock is allowed to keep running.
          next unless suppressible_source?(cart, normalized)

          cart.update_columns(notes: 'Superseded', updated_at: Time.current)
        end
        touched += 1
      end

      Rails.logger.info(
        "[webhook/process] shop=#{shop.id} suppression refs=#{references.first(3).inspect} touched=#{touched}"
      )
      :ok
    end

    def suppressible_source?(cart, normalized)
      cart.checkout_id.to_s.start_with?('flo_cart_', 'flo_browse_') &&
        Array(normalized.suppresses).any?
    end

    def already_recovered?(shop, normalized)
      references = Array(normalized.external_references).compact_blank
      return false if references.empty?

      shop.abandoned_carts.where(checkout_id: references).where("lower(coalesce(notes, '')) = 'recovered'").exists?
    end

    def source_for(normalized)
      normalized.source_external_id.to_s.start_with?('flo_') ? 'shopflo' : 'custom'
    end

    def mirror_to_slack(record)
      pretty = JSON.pretty_generate(record.payload)
      pretty = "#{pretty[0, MAX_SLACK_TEXT]}\n… (truncated)" if pretty.length > MAX_SLACK_TEXT
      SlackNotifyJob.perform_async(
        ":inbox_tray: *#{record.provider} #{record.event_name}* shop=#{record.shop_id} (#{Rails.env})\n```#{pretty}```"
      )
    rescue StandardError => e
      Rails.logger.warn("[webhook/process] slack mirror failed: #{e.class}: #{e.message}")
      nil
    end
  end
end
