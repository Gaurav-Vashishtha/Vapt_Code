# frozen_string_literal: true

module MerchantWhatsapp
  class DispatchEventJob < ApplicationJob
    sidekiq_options queue: "administration", retry: 1

    def perform(event_key, shop_id = nil, uninstalled_shop_id = nil)
      MerchantWhatsappRule.for_event(event_key).find_each do |rule|
        scheduled = ensure_scheduled(rule, shop_id, uninstalled_shop_id)
        next unless scheduled

        Dispatcher.deliver(scheduled) if scheduled.scheduled_at.nil? || scheduled.scheduled_at <= Time.current
      end
    rescue => e
      Rails.logger.error("[MerchantWhatsapp::DispatchEventJob] #{event_key} #{e.class}: #{e.message}")
    end

    private

    def ensure_scheduled(rule, shop_id, uninstalled_shop_id)
      if rule.target == "uninstalled_shops"
        return nil if uninstalled_shop_id.blank?

        record = UninstalledShop.find_by(id: uninstalled_shop_id)
        return nil unless record

        find_or_create(rule, uninstalled_shop_id: record.id, domain: record.shop_domain)
      else
        return nil if shop_id.blank?

        record = Shop.find_by(id: shop_id)
        return nil unless record

        find_or_create(rule, shop_id: record.id, domain: record.shopify_domain)
      end
    end

    def find_or_create(rule, shop_id: nil, uninstalled_shop_id: nil, domain: nil)
      ScheduledMerchantWhatsapp.create!(
        merchant_whatsapp_rule_id: rule.id, shop_id: shop_id, uninstalled_shop_id: uninstalled_shop_id,
        shopify_domain: domain, status: "pending", scheduled_at: Time.current + rule.delay_offset
      )
    rescue ActiveRecord::RecordNotUnique
      ScheduledMerchantWhatsapp.find_by(
        merchant_whatsapp_rule_id: rule.id, shop_id: shop_id, uninstalled_shop_id: uninstalled_shop_id
      )
    end
  end
end
