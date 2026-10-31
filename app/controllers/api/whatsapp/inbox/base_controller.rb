# frozen_string_literal: true

module Api
  module Whatsapp
    module Inbox
      class BaseController < AuthenticatedController
        INBOX_UNSUPPORTED_BUTTONS = %w[OTP COPY_CODE CATALOG MPM FLOW].freeze

        before_action :ensure_inbox_enabled

        rescue_from ActiveRecord::RecordNotFound do
          render_error('not_found', 'Not found', :not_found)
        end

        rescue_from ShopifyApp::LoginProtection::ShopifyDomainNotFound do
          render_error('session_expired', 'Your session expired. Please try again.', :unauthorized)
        end

        private

        def ensure_inbox_enabled
          render_error('not_found', 'Not found', :not_found) if ENV.fetch("WHATSAPP_INBOX_DISABLED", nil).present?
        end

        def current_agent
          @current_agent ||= ::Whatsapp::Inbox::AgentResolver.call(shop: @shop, request: request)
        end

        def inbox_accounts
          @inbox_accounts ||= @shop.whatsapp_accounts.where(custom_branded_client_id: nil)
        end

        def load_conversation
          @conversation = WhatsappConversation.where(shop_id: @shop.id).find(params[:conversation_id] || params[:id])
        end

        def render_error(code, message, status = :unprocessable_entity, extra = {})
          render json: { error: message, code: code }.merge(extra), status: status
        end

        def session_token
          request.headers['Authorization'].to_s[/\ABearer (.+)\z/, 1]
        end

        def conversation_detail(conversation)
          ::Whatsapp::Inbox::ConversationSerializer.detail(conversation, shop: @shop, current_agent: current_agent)
        end

        def truthy_param?(value)
          ActiveModel::Type::Boolean.new.cast(value.presence) == true
        end

        def inbox_templates(conversation)
          account_id = conversation.whatsapp_account_id
          return WhatsappTemplate.none if account_id.nil? || !inbox_accounts.where(id: account_id).exists?

          WhatsappTemplate.approved
                          .where(whatsapp_account_id: account_id)
                          .where.not(category: :authentication)
                          .where("whatsapp_templates.event_type_key IS NULL OR whatsapp_templates.event_type_key <> 'cod_verification'")
        end

        # The inbox only fills numbered BODY placeholders, so anything that needs
        # other send-time parameters (dynamic URL buttons, header variables, OTP /
        # catalog / flow buttons, named params) would be rejected by Meta.
        def inbox_template_pickable?(template)
          return false if template.url_button_present?

          components = ::Whatsapp::TemplateComponents
          body = components.text_of(template.components, 'BODY')
          return false if body.blank? || body.match?(/\{\{\s*[^\d\s}]/)
          return false unless header_sendable?(template, components.find(template.components, 'HEADER'))

          components.buttons(template.components).none? do |b|
            type = b['type'].to_s.upcase
            INBOX_UNSUPPORTED_BUTTONS.include?(type) || (type == 'URL' && b['url'].to_s.include?('{{'))
          end
        end

        def inbox_template_header_type(template)
          header = ::Whatsapp::TemplateComponents.find(template.components, 'HEADER')
          return 'none' unless header

          format = header['format'].presence || 'TEXT'
          %w[TEXT IMAGE VIDEO DOCUMENT].include?(format) ? format.downcase : 'none'
        end

        def header_sendable?(template, header)
          return true if header.nil?

          format = header['format'].presence || 'TEXT'
          case format
          when 'TEXT' then !header['text'].to_s.include?('{{')
          when 'IMAGE' then true
          when 'VIDEO', 'DOCUMENT' then static_media_header?(template, header)
          else false
          end
        end

        def static_media_header?(template, header)
          hm = template.header_media.is_a?(Hash) ? template.header_media : {}
          return true if hm['media_id'].present? || hm['url'].present?
          return true if hm['source'] == 'url' && hm['value'].present?

          handle = Array(header.dig('example', 'header_handle')).first.to_s
          handle.start_with?('http') && !template.meta_sample_link?(handle)
        end
      end
    end
  end
end
