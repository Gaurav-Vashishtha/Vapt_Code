# frozen_string_literal: true

module Api
  module Whatsapp
    module Inbox
      class SettingsController < BaseController
        SETTING_KEYS = %w[read_receipts auto_label welcome away keyword_rules unanswered_email].freeze

        def show
          render json: { settings: setting.as_inbox_json }
        end

        def update
          setting.apply_api_attributes(params.to_unsafe_h.slice(*SETTING_KEYS))
          if setting.save
            render json: { settings: setting.as_inbox_json }
          else
            render_error('invalid', setting.errors.full_messages.first)
          end
        end

        private

        def setting
          @setting ||= WhatsappInboxSetting.for(@shop)
        end
      end
    end
  end
end
