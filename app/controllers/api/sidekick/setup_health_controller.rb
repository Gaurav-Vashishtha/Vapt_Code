# frozen_string_literal: true

module Api
  module Sidekick
    # A checklist of common reasons COD King "isn't working", each with the app
    # page that fixes it (paths match extensions/codk-sidekick-data/src/app-map.json).
    class SetupHealthController < BaseController
      FAILURE_RATE_WARN = 0.2

      def show
        checks = cached('setup_health') { build_checks }

        render json: {
          summary: {
            ok: checks.count { |c| c[:status] == 'ok' },
            warnings: checks.count { |c| c[:status] == 'warning' },
            problems: checks.count { |c| c[:status] == 'problem' }
          },
          checks: checks,
          results: checks.reject { |c| c[:status] == 'ok' }.map { |c| { url: "app:/#{c[:fix_path]}" } }.uniq
        }
      end

      private

      def build_checks
        setting = @shop.setting
        [
          check('Subscription plan', @shop.charge_id.present?, 'problem',
                'No active COD King plan — paid features stay off until a plan is approved.', '/subscription'),
          check('COD King form', setting&.cod_form_enabled, 'warning',
                'The COD King order form is turned off.', '/features/ui-customization'),
          check('Order verification', setting&.enable_pre_order_otp || setting&.sms || setting&.auto_verify, 'warning',
                'No OTP or WhatsApp verification is on, so COD orders are not being verified.', '/features/otp/pre-order'),
          check('Customer notifications',
                setting&.confirmation_whatsapp || setting&.confirmation_sms_enabled || setting&.fulfilment_whatsapp, 'warning',
                'No order confirmation or fulfilment messages are on.', '/features/notifications'),
          check('WhatsApp templates', !@shop.whatsapp_templates.where(status: %i[rejected paused disabled]).exists?, 'warning',
                'Some branded WhatsApp templates are rejected, paused or disabled.', '/features/whatsapp/templates'),
          check('Message delivery', failure_rate < FAILURE_RATE_WARN, 'warning',
                "#{(failure_rate * 100).round}% of messages in the last 7 days failed.", '/usage-analytics/message-logs'),
          check('Free message credit', @shop.charge_id.present? || wallet_balance.nil? || wallet_balance.positive?, 'problem',
                'Free trial message credit is used up and there is no plan, so SMS/WhatsApp sends may stop.', '/subscription')
        ]
      end

      def check(name, passed, severity, message, fix_path)
        { name: name, status: passed ? 'ok' : severity, message: passed ? nil : message, fix_path: fix_path }.compact
      end

      def failure_rate
        @failure_rate ||= begin
          twilio = TwilioLog.where(shop_id: @shop.id, created_at: 7.days.ago..)
          branded = @shop.whatsapp_message_logs.where(created_at: 7.days.ago..)
          total = twilio.count + branded.count
          failed = twilio.where("status IN ('failed', 'undelivered') OR status LIKE '{%'").count + branded.failed.count
          total.zero? ? 0.0 : failed.to_f / total
        end
      end

      def wallet_balance
        return @wallet_balance if defined?(@wallet_balance)

        wallet = Wallet.find_by(shopify_domain: @shop.shopify_domain)
        @wallet_balance = wallet && (wallet.total_balance.to_f - wallet.balance_used.to_f)
      end
    end
  end
end
