# frozen_string_literal: true

module MerchantWhatsapp
  class SchedulerJob < ApplicationJob
    sidekiq_options queue: "administration", retry: 1

    def perform
      MerchantWhatsappRule.scheduled.where.not(category: "digest").find_each do |rule|
        process_rule(rule)
      end
      dispatch_due_event_rows
    rescue => e
      Rails.logger.error("[MerchantWhatsapp::SchedulerJob] #{e.class}: #{e.message}")
    end

    private

    def process_rule(rule)
      if rule.target == "uninstalled_shops"
        CandidateFinder.uninstalled_ids(rule).each { |id| ensure_uninstalled(rule, id) }
      else
        CandidateFinder.shop_ids(rule).each { |id| ensure_shop(rule, id) }
      end
      dispatch_due(rule)
    rescue => e
      Rails.logger.error("[MerchantWhatsapp::SchedulerJob] rule=#{rule.slug} #{e.class}: #{e.message}")
    end

    def ensure_shop(rule, shop_id)
      shop = Shop.find_by(id: shop_id)
      return unless shop && shop.owner_phone.present?

      ScheduledMerchantWhatsapp.create!(
        merchant_whatsapp_rule_id: rule.id, shop_id: shop.id, shopify_domain: shop.shopify_domain,
        status: "pending", scheduled_at: ScheduledAt.for(rule, shop)
      )
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def ensure_uninstalled(rule, uninstalled_shop_id)
      record = UninstalledShop.find_by(id: uninstalled_shop_id)
      return unless record && record.phone.present?

      ScheduledMerchantWhatsapp.create!(
        merchant_whatsapp_rule_id: rule.id, uninstalled_shop_id: record.id, shopify_domain: record.shop_domain,
        status: "pending", scheduled_at: ScheduledAt.for(rule, record)
      )
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def dispatch_due(rule)
      ScheduledMerchantWhatsapp.pending
                               .where(merchant_whatsapp_rule_id: rule.id)
                               .where("scheduled_at <= ?", Time.current)
                               .find_each { |scheduled| Dispatcher.deliver(scheduled) }
    end

    def dispatch_due_event_rows
      event_rule_ids = MerchantWhatsappRule.active.where(trigger_type: "event").pluck(:id)
      return if event_rule_ids.empty?

      ScheduledMerchantWhatsapp.pending
                               .where(merchant_whatsapp_rule_id: event_rule_ids)
                               .where("scheduled_at <= ?", Time.current)
                               .find_each { |scheduled| Dispatcher.deliver(scheduled) }
    end
  end
end
