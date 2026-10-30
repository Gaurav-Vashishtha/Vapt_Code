# frozen_string_literal: true

module Api
  module Whatsapp
    module Ai
      class SettingsController < BaseController
        KEYS = %w[status reply_mode agent_name tone skills discount allow_cancel knowledge handoff_text test_numbers
                  team_timeout_minutes daily_reply_limit].freeze

        def show
          render json: payload
        end

        def update
          was_off = ai_setting.agent_off?
          ai_setting.apply_api_attributes(params.to_unsafe_h.slice(*KEYS))
          return render_error('invalid', ai_setting.errors.full_messages.first) unless ai_setting.save

          ::Whatsapp::Ai::Wallet.grant_free!(@shop) if was_off && ai_setting.active?
          @wallet = nil
          render json: payload
        end

        def import_knowledge
          text = ::Whatsapp::Ai::KnowledgeImporter.call(@shop, ai_setting)
          render json: { knowledge: text }
        rescue ::Whatsapp::Ai::KnowledgeImporter::Error => e
          render_error('import_failed', e.message)
        end

        private

        def payload
          {
            settings: ai_setting.as_api_json,
            wallet: wallet.as_api_json,
            config: config_json,
            store_name: store_name
          }
        end

        def store_name
          account = @shop.whatsapp_accounts.where(custom_branded_client_id: nil).order(:id).first
          account&.verified_name.to_s.strip.presence ||
            @shop.shopify_domain.to_s.delete_suffix('.myshopify.com').tr('-', ' ').split.map(&:capitalize).join(' ')
        end
      end
    end
  end
end
