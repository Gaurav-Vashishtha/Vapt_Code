# frozen_string_literal: true

module MerchantWhatsapp
  module Dispatcher
    module_function

    PERMANENT_SKIPS = %w[inactive_rule no_template shop_gone no_recipient opted_out not_eligible].freeze

    def deliver(scheduled, context: {})
      return :done if %w[sent skipped failed].include?(scheduled.status)

      rule = scheduled.merchant_whatsapp_rule
      return skip(scheduled, "inactive_rule") unless rule&.active?

      template = rule.owner_whatsapp_template
      return skip(scheduled, "no_template") unless template

      target_type = rule.target == "uninstalled_shops" ? :uninstalled_shop : :shop
      record = target_type == :uninstalled_shop ? scheduled.uninstalled_shop : scheduled.shop
      return skip(scheduled, "shop_gone") if record.nil?

      domain = record.try(:shopify_domain) || record.try(:shop_domain)
      recipient = record.try(:owner_phone) || record.try(:phone)
      # owner_phone often syncs a few minutes after install — defer so the
      # hourly scheduler retries, and only give up after 48h without a phone.
      if recipient.blank?
        return scheduled.created_at > 48.hours.ago ? defer(scheduled, "no_recipient") : skip(scheduled, "no_recipient")
      end
      return skip(scheduled, "opted_out") if MerchantWhatsappOptOut.opted_out?(domain)
      return skip(scheduled, "not_eligible") unless eligible?(rule, record, target_type)

      return defer(scheduled, "frequency_cap") if FrequencyGuard.recent_send?(domain)
      return defer(scheduled, "quiet_hours") unless FrequencyGuard.within_quiet_hours?(record)
      return defer(scheduled, "preview") unless Config.live?

      account = OwnerWhatsappAccount.current
      return defer(scheduled, "sender_not_ready") unless account&.ready_to_send?

      send_now(scheduled, rule, template, record, domain, recipient, target_type, context)
    end

    def eligible?(rule, record, target_type)
      if rule.scheduled?
        target_type == :uninstalled_shop ?
          EmailRuleEvaluatorService.rule_satisfied_for_uninstalled_shop?(rule, record) :
          EmailRuleEvaluatorService.rule_satisfied_for_shop?(rule, record)
      else
        EmailRuleEvaluatorService.conditions_satisfied?(rule, record, target_type)
      end
    rescue => e
      Rails.logger.warn("[MerchantWhatsapp::Dispatcher] eligibility check failed rule=#{rule.id}: #{e.message}")
      false
    end

    def send_now(scheduled, rule, template, record, domain, recipient, target_type, context)
      mapping = rule.variable_mapping.presence || template.variable_mapping
      body_params = VariableResolver.body_parameters(template, record, context, mapping: mapping)
      button_params = resolve_button_params(rule, template, domain)

      log = MerchantWhatsappLog.create!(
        merchant_whatsapp_rule_id: rule.id,
        scheduled_merchant_whatsapp_id: scheduled.id,
        shop_id: target_type == :shop ? record.id : nil,
        uninstalled_shop_id: target_type == :uninstalled_shop ? record.id : nil,
        shopify_domain: domain,
        event_key: rule.event_key.presence || rule.slug,
        template_name: template.name,
        recipient: recipient,
        status: "queued",
        dry_run: false,
        payload_snapshot: { "body_parameters" => body_params }
      )

      meta_id = Sender.call(template: template, recipient: recipient, body_parameters: body_params, button_params: button_params)
      log.update!(meta_message_id: meta_id, status: "sent", sent_at: Time.current)
      scheduled.update!(status: "sent", sent_at: Time.current, merchant_whatsapp_log_id: log.id, skip_reason: nil)
      :sent
    rescue => e
      Rails.logger.error("[MerchantWhatsapp::Dispatcher] send failed scheduled=#{scheduled.id}: #{e.class}: #{e.message}")
      log&.update(status: "failed", failed_at: Time.current, error_message: e.message.to_s.truncate(500))
      scheduled.update(status: "failed", merchant_whatsapp_log_id: log&.id, skip_reason: e.message.to_s.truncate(200))
      :failed
    end

    # One parameter per dynamic URL button (Meta 131008 otherwise). cta_config
    # can override per index ({"buttons": [{"index": 0, "slug": "..."}]}) or
    # globally ("button_slug"); the default slug is the shop domain, matching
    # the ?shop={{1}} pattern the owner templates use.
    def resolve_button_params(rule, template, domain)
      cta = rule.cta_config.is_a?(Hash) ? rule.cta_config : {}
      global = cta["button_slug"].presence
      overrides = Array(cta["buttons"]).each_with_object({}) do |b, acc|
        acc[b["index"].to_i] = b["slug"].presence if b.is_a?(Hash)
      end

      template.dynamic_url_button_indexes.map do |i|
        { index: i, slug: overrides[i] || global || domain }
      end
    end

    def skip(scheduled, reason)
      scheduled.update(status: "skipped", skip_reason: reason)
      :skipped
    end

    def defer(scheduled, reason)
      scheduled.update(skip_reason: reason) unless scheduled.skip_reason == reason
      :deferred
    end
  end
end
