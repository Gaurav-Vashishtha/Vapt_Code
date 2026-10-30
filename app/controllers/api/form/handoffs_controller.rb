# frozen_string_literal: true

module Api
  module Form
    # POST /api/form/handoff (D.8): partial / prepaid hand-off to Shopify checkout.
    class HandoffsController < BaseController
      def create
        result = CodForm::HandoffService.call(
          shop: shop, config: shop_config, session: form_session, params: body, ip: request.remote_ip.to_s
        )
        render_ok(result.except("ok"))
      end
    end
  end
end
