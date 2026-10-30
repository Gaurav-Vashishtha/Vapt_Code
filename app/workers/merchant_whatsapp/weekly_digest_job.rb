# frozen_string_literal: true

module MerchantWhatsapp
  class WeeklyDigestJob < ApplicationJob
    sidekiq_options queue: "administration", retry: 1

    def perform
      return unless Config.enabled?

      rule = MerchantWhatsappRule.active.find_by(trigger_type: "scheduled", category: "digest")
      return unless rule

      template = rule.owner_whatsapp_template
      return unless template

      scope = EmailRuleEvaluatorService.apply_conditions_scope_shop(Shop.includes(:setting), rule)
      scope = scope.where(shopify_domain: Config.test_domains) if Config.restricted_to_test_domains?
      scope.find_each { |shop| deliver(rule, template, shop) }
    rescue => e
      Rails.logger.error("[MerchantWhatsapp::WeeklyDigestJob] #{e.class}: #{e.message}")
    end

    private

    def deliver(rule, template, shop)
      domain = shop.shopify_domain
      recipient = shop.owner_phone
      return if recipient.blank?
      return if MerchantWhatsappOptOut.opted_out?(domain)
      return if FrequencyGuard.recent_send?(domain)
      return unless FrequencyGuard.within_quiet_hours?(shop)

      context = DigestStats.for(shop)
      live = Config.live?
      log = MerchantWhatsappLog.create!(
        merchant_whatsapp_rule_id: rule.id, shop_id: shop.id, shopify_domain: domain,
        event_key: "weekly_digest", template_name: template.name, recipient: recipient,
        status: live ? "queued" : "dry_run", dry_run: !live, payload_snapshot: { "context" => context }
      )
      return unless live

      meta_id = Sender.call(template: template, recipient: recipient,
                            body_parameters: VariableResolver.body_parameters(template, shop, context))
      log.update!(meta_message_id: meta_id, status: "sent", sent_at: Time.current)
    rescue => e
      Rails.logger.error("[MerchantWhatsapp::WeeklyDigestJob] deliver shop=#{shop.id} #{e.class}: #{e.message}")
    end
  end
end
