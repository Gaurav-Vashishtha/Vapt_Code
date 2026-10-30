# frozen_string_literal: true

module Api
  module Form
    # POST /api/form/quote (D.2). Ineligibility, missing rates and invalid codes are data in a
    # 200, not errors.
    class QuotesController < BaseController
      def create
        if form_session.order_id.present?
          snapshot = form_session.quote_snapshot.is_a?(Hash) ? form_session.quote_snapshot.except(CodForm::OrderService::RESPONSE_KEY) : {}
          return render_ok("seq" => body["seq"], "quote" => snapshot)
        end

        quote = CodForm::QuoteService.call(
          shop: shop, config: shop_config, session: form_session, params: body, stage: "quote", ip: request.remote_ip.to_s
        )
        render_ok("seq" => body["seq"], "quote" => quote)
      end
    end
  end
end
