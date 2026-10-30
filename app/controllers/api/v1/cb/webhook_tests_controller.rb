# frozen_string_literal: true

module Api
  module V1
    module Cb
      # Fire a sample webhook at the configured partner URL to test the
      # integration end-to-end (signature verification included). The sample
      # is a real delivery in every way — recorded in the delivery log with
      # fields "test:<event>" — plus an X-CB-Test: true header and
      # wamid.TEST… ids so the consumer can tell it apart.
      class WebhookTestsController < BaseController
        # POST /api/v1/cb/webhook_tests { shop_domain, event }
        # event: delivery_status | inbound_reply | template_review
        def create
          result = CustomBranded::WebhookTester.call(client: client, event: params[:event])
          render json: result, status: :ok
        rescue CustomBranded::WebhookTester::Error => e
          render_error(e.message, :unprocessable_entity)
        end
      end
    end
  end
end
