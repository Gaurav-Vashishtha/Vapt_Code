# frozen_string_literal: true

module CodForm
  module Abandonment
    # ABN-1 (ARCHITECTURE.md I.4). sidekiq-cron: every 5 minutes, queue low.
    #
    # A session becomes an abandoned form when it
    #   - is open / otp_pending / blocked, has no order and is not a test session,
    #   - has a phone or an email,
    #   - has been idle for general.abandonment.delay_minutes (default and UI-fixed: 15),
    # and the shop
    #   - is in COD Form mode with general.abandonment.enabled and the gate abandonment_recovery,
    #   - already has abandoned-cart messages on (Setting#abandoned_cart_enabled or ac_whatsapp,
    #     or a BSP abandoned_cart binding; product decision 7).
    # A buyer who has since ordered with the same phone or email in this shop is skipped.
    class SweepJob < ApplicationJob
      sidekiq_options queue: "low", retry: false

      DEFAULT_DELAY_MINUTES = 15
      MIN_DELAY_MINUTES = 5
      LOOKBACK = 24.hours
      PER_SHOP_LIMIT = 500
      ELIGIBILITY_TTL = 10.minutes
      LOCK_KEY = "codf:abandon:sweep"
      LOCK_TTL = 4.minutes

      def perform
        return unless CodForm::Cache.store.write(LOCK_KEY, 1, unless_exist: true, expires_in: LOCK_TTL)

        begin
          # Shops first, then their sessions: sessions of shops without abandoned-cart messages
          # stay open and must never crowd out the shops that have them on.
          candidates.distinct.pluck(:shop_id).each do |shop_id|
            sweep_shop(shop_id)
          rescue StandardError => e
            Rails.logger.warn("[codf/abandon] sweep shop=#{shop_id} failed: #{e.class}")
          end
        ensure
          CodForm::Cache.store.delete(LOCK_KEY)
        end
      end

      private

      def candidates
        CodForm::Session
          .where(status: MarkAbandonedService::ABANDONABLE, order_id: nil, is_test: false)
          .where("updated_at < ?", MIN_DELAY_MINUTES.minutes.ago)
          .where("updated_at > ?", LOOKBACK.ago)
          .where("coalesce(contact->>'phone_e164', '') <> '' OR coalesce(contact->>'email', '') <> ''")
      end

      def sweep_shop(shop_id)
        delay = CodForm::Cache.store.fetch("codf:abandon:delay:#{shop_id}", expires_in: ELIGIBILITY_TTL) do
          shop = Shop.find_by(id: shop_id)
          shop ? delay_minutes_for(shop).to_i : 0
        end
        return unless delay.positive?

        shop = Shop.find_by(id: shop_id)
        return if shop.nil?

        candidates.where(shop_id: shop_id).where("updated_at < ?", delay.minutes.ago)
                  .order(:updated_at).limit(PER_SHOP_LIMIT).each do |session|
          next if ordered_since?(shop, session)

          MarkAbandonedService.call(session)
        rescue StandardError => e
          Rails.logger.warn("[codf/abandon] shop=#{shop_id} session=#{session.id} failed: #{e.class}")
        end
      end

      # Delay in minutes when abandoned forms are active for the shop, else nil.
      def delay_minutes_for(shop)
        config = CodForm::ShopConfig.for(shop)
        return nil unless config.cod_form_mode?

        general = config.general.is_a?(Hash) ? config.general : {}
        abandonment = general["abandonment"].is_a?(Hash) ? general["abandonment"] : {}
        return nil if abandonment["enabled"] == false

        return nil unless messages_on?(shop)
        return nil unless CodForm::Integrations::Registry.gate?(shop, "abandonment_recovery")

        minutes = abandonment["delay_minutes"].to_i
        minutes = DEFAULT_DELAY_MINUTES unless minutes.positive?
        [minutes, MIN_DELAY_MINUTES].max
      end

      # Product decision 7: abandoned forms only feed shops that already send abandoned-cart
      # messages — the legacy SMS / WhatsApp schedules on Setting, or a BSP abandoned_cart
      # template binding (those shops are served by Whatsapp::ScheduleAbandonedCartRemindersJob).
      def messages_on?(shop)
        setting = shop.setting
        return true if setting && (setting.abandoned_cart_enabled || setting.ac_whatsapp)

        shop.bsp_abandoned_cart?
      end

      def ordered_since?(shop, session)
        scope = CodForm::Session.where(shop_id: shop.id).where.not(order_id: nil)
                                .where("ordered_at >= ?", session.created_at)
        contact = session.contact.is_a?(Hash) ? session.contact : {}
        phone = session.phone_normalized.presence || CodForm::BlockEntry.normalize("phone", contact["phone_e164"])
        email = session.email_normalized.presence || contact["email"].to_s.strip.downcase
        return true if phone.present? && scope.where(phone_normalized: phone).exists?
        return true if email.present? && scope.where(email_normalized: email).exists?

        false
      end
    end
  end
end
