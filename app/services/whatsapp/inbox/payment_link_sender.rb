# frozen_string_literal: true

module Whatsapp
  module Inbox
    class PaymentLinkSender
      ERRORS = %i[not_cod not_pending disabled not_eligible paused rate_limited mismatch send_failed].freeze
      RATE_LIMIT = 10.minutes

      # SendPrepaidMessageService falls back to SMS / the shared number when the
      # merchant's WhatsApp send fails mid-way; the inbox must never do that (PM decision 7).
      class WhatsappOnlyPrepaidMessage < NetworkServices::SendPrepaidMessageService
        private

        def send_without_bsp(_setting)
          nil
        end
      end

      def self.call(conversation:, order_confirmation:, agent:)
        new(conversation, order_confirmation, agent).call
      end

      def self.shop_reason(shop)
        setting = shop&.setting
        return :disabled unless setting&.prepaid_notif
        return :disabled if setting.locked
        return :paused if NetworkServices::WhatsappPrepaidBspService.paused?(shop)
        return :not_eligible unless NetworkServices::WhatsappPrepaidBspService.eligible?(shop)

        nil
      end

      def self.order_reason(order_confirmation)
        return :not_cod unless order_confirmation.is_cod_order
        return :not_pending unless ::Whatsapp::ContactOrderStats::UNCONFIRMED_COD_STATUSES.include?(order_confirmation.status.to_s)

        nil
      end

      def initialize(conversation, order_confirmation, agent)
        @conversation = conversation
        @order_confirmation = order_confirmation
        @agent = agent
        @shop = conversation.shop
      end

      def call
        return :mismatch unless matches_conversation?

        reason = self.class.order_reason(@order_confirmation) || self.class.shop_reason(@shop)
        return reason if reason
        return :rate_limited unless Rails.cache.write(cache_key, @agent&.id || 0, expires_in: RATE_LIMIT, unless_exist: true)

        @rate_limit_taken = true

        result = WhatsappOnlyPrepaidMessage.call(@shop, @order_confirmation, send_key: "inbox#{Time.current.to_i}")
        return :sent if result.is_a?(WhatsappMessageLog)

        Rails.cache.delete(cache_key)
        result == :paused ? :paused : :send_failed
      rescue StandardError => e
        Rails.logger.error("[Whatsapp::Inbox::PaymentLinkSender] conv=#{@conversation&.id} oc=#{@order_confirmation&.id} #{e.class}: #{e.message}")
        Rails.cache.delete(cache_key) if @rate_limit_taken
        :send_failed
      end

      private

      def matches_conversation?
        @order_confirmation.present? &&
          @order_confirmation.shop_id == @conversation.shop_id &&
          OrderLookup.last10(@order_confirmation.customer_number) == @conversation.phone_last10.to_s
      end

      def cache_key
        "inbox:paylink:#{@order_confirmation.id}"
      end
    end
  end
end
