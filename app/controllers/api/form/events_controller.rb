# frozen_string_literal: true

module Api
  module Form
    # POST /api/form/events (D.10). Always 204: analytics must never surface an error to the
    # storefront. The token is optional (button views happen before a session exists).
    class EventsController < BaseController
      MAX_EVENTS = 20

      skip_before_action :authenticate_session!
      before_action :authenticate_session_if_present

      rescue_from StandardError, with: :no_content
      rescue_from CodForm::Errors::ApiError, with: :no_content

      def create
        events = body["events"].is_a?(Array) ? body["events"].first(MAX_EVENTS) : []
        # A shop whose form is not live records nothing, except for staff test sessions.
        if events.any? && CodForm::Availability.usable?(@availability, test: form_session&.is_test == true)
          CodForm::EventIngestService.call(
            shop: shop, session: form_session, client_id: body["client_id"].to_s[0, 64],
            events: events, request_meta: request_meta
          )
        end
        head :no_content
      end

      private

      def no_content(_error = nil)
        head :no_content
      end
    end
  end
end
