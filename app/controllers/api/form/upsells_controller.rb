# frozen_string_literal: true

module Api
  module Form
    # POST /api/form/upsell_accept (D.9, OFF-10).
    class UpsellsController < BaseController
      def accept
        offer_id = body["offer_id"]
        result =
          if body["accept"] == false
            CodForm::UpsellService.decline(session: form_session, offer_id: offer_id)
          else
            CodForm::UpsellService.accept(session: form_session, offer_id: offer_id, shop: shop)
          end
        render_ok(result.except("ok"))
      end
    end
  end
end
