# frozen_string_literal: true

module Api
  module Form
    # POST /api/form/orders (D.6) and /api/form/orders/status (D.7).
    class OrdersController < BaseController
      def create
        result = CodForm::OrderService.call(
          shop: shop, config: shop_config, session: form_session, params: body, request_meta: request_meta
        )
        render_result(result)
      end

      def status
        render_result(CodForm::OrderService.status(session: form_session))
      end

      private

      def render_result(result)
        response.headers["Cache-Control"] = "no-store"
        render json: result.body, status: result.status
      end
    end
  end
end
