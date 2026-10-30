# frozen_string_literal: true

module Api
  module Whatsapp
    module Ai
      class BaseController < ::Api::Whatsapp::Inbox::BaseController
        private

        def ai_setting
          @ai_setting ||= WhatsappAiSetting.for(@shop)
        end

        def wallet
          @wallet ||= WhatsappAiWallet.for(@shop)
        end

        def config_json
          { 'configured' => ::Whatsapp::Ai::Config.enabled?, 'model' => ::Whatsapp::Ai::Config.model }
        end
      end
    end
  end
end
