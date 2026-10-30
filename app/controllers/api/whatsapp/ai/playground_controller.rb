# frozen_string_literal: true

module Api
  module Whatsapp
    module Ai
      class PlaygroundController < BaseController
        MAX_MESSAGES = 20

        def create
          messages = Array(params.to_unsafe_h['messages']).last(MAX_MESSAGES)
          return render_error('invalid', 'Type a customer message first.') if messages.empty?

          setting = ai_setting.dup
          setting.apply_api_attributes(params.to_unsafe_h['settings']) if params[:settings].present?
          result = ::Whatsapp::Ai::Responder.playground(@shop, messages: messages, phone: params[:phone], setting: setting)
          render json: result
        rescue ::Whatsapp::Ai::Responder::RateLimited => e
          render_error('rate_limited', e.message, :too_many_requests)
        rescue ::Whatsapp::Ai::Responder::Error => e
          render_error('not_configured', e.message)
        end
      end
    end
  end
end
