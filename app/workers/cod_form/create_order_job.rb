# frozen_string_literal: true

module CodForm
  # Background half of an order submit when cod_form_global_settings.async_orders is on
  # (ARCHITECTURE.md F.2, ORD-9). The compare-and-set already happened in the request, so the
  # job is never retried: a failure resets the session and the buyer retries (ORD-7).
  class CreateOrderJob < ApplicationJob
    sidekiq_options queue: "critical", retry: false

    def perform(session_id)
      CodForm::OrderService.finish_async(session_id)
    end
  end
end
