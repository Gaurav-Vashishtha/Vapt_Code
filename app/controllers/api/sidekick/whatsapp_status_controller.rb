# frozen_string_literal: true

module Api
  module Sidekick
    class WhatsappStatusController < BaseController
      WINDOW = 30.days
      DELIVERED = %w[delivered read].freeze

      def show
        setting = @shop.setting
        since = WINDOW.ago

        render json: {
          results: [
            resource_link(
              type: 'whatsapp_status',
              id: @shop.id,
              name: "WhatsApp — #{@shop.shopify_domain}",
              meta: {
                order_confirmation_whatsapp_enabled: setting&.confirmation_whatsapp,
                fulfilment_whatsapp_enabled: setting&.fulfilment_whatsapp,
                abandoned_cart_whatsapp_enabled: setting&.ac_whatsapp,
                first_purchase_whatsapp_enabled: setting&.first_purchase_whatsapp_enabled,
                branded_accounts_connected: @shop.whatsapp_accounts.count,
                cod_king_number_messages_30d: cod_king_number_messages(since),
                branded_number_messages_30d: branded_messages(since),
                branded_templates: templates
              }
            )
          ]
        }
      end

      private

      # Approval state of templates on the merchant's own number; rejected or
      # paused ones are the usual reason branded messages stop.
      def templates
        scope = @shop.whatsapp_templates
        return nil unless scope.exists?

        problems = scope.where(status: %i[rejected paused disabled]).order(updated_at: :desc).limit(5).map do |t|
          reason = t.rejection_reason unless t.rejection_reason.to_s.casecmp?('none')
          { name: t.name, language: t.language, status: t.status, used_for: t.event_type_key.presence, reason: reason.presence }.compact
        end
        { by_status: scope.group(:status).count, needs_attention: problems.presence }.compact
      end

      # Messages sent from the shared COD King number (Twilio).
      def cod_king_number_messages(since)
        TwilioLog.where(shop_id: @shop.id, created_at: since..)
                 .where('ver_type ILIKE ?', '%whatsapp%')
                 .count
      end

      # Messages sent from the merchant's own number. `read` counts as
      # delivered: Meta moves a delivered message on to read.
      def branded_messages(since)
        counts = @shop.whatsapp_message_logs.where(created_at: since..).group(:status).count
        {
          sent: counts.values.sum,
          delivered: DELIVERED.sum { |s| counts[s].to_i },
          read: counts['read'].to_i,
          failed: counts['failed'].to_i,
          queued: counts['queued'].to_i
        }
      end
    end
  end
end
