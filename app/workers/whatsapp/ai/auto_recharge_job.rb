# frozen_string_literal: true

module Whatsapp
  module Ai
    class AutoRechargeJob < ApplicationJob
      sidekiq_options queue: 'default', retry: false

      LOCK_TTL = 10.minutes

      def perform(shop_id)
        shop = Shop.find_by(id: shop_id)
        return unless shop
        return unless Rails.cache.write("wa_ai:auto_recharge:#{shop.id}", 1, expires_in: LOCK_TTL, unless_exist: true)

        result = Recharge.auto_recharge!(shop)
        Rails.logger.info("[Whatsapp::Ai::AutoRechargeJob] shop=#{shop.id} result=#{result}")
      rescue StandardError => e
        Rails.logger.error("[Whatsapp::Ai::AutoRechargeJob] shop=#{shop_id} #{e.class}: #{e.message}")
      end
    end
  end
end
