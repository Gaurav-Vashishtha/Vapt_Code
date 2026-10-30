# frozen_string_literal: true

module CodForm
  # Webhook side of form orders (ARCHITECTURE.md F.5). Called from
  # OrderConfirmationCreateJob#perform. Both entry points swallow every error: the existing
  # order pipeline must never fail because of the form module.
  class OrderWebhookHook
    SESSION_ATTRIBUTE = "_codkFormSessionId"
    FEE_ATTRIBUTE = "_codkCodFee"
    FORM_SOURCE = "codking_form"
    DRAFT_SOURCE = "shopify_draft_order"

    class << self
      # Returns params unchanged unless the order was created by the COD Form for the session
      # named in its `_codkFormSessionId` note attribute. For a form order it returns a copy
      # with source_name = 'codking_form' and '_codk_form' = true, so the job treats it like a
      # checkout COD order (messaging, verification) and does not add the COD fee again.
      #
      # "Created by the form" = a draft order (only apps and staff can create those) whose
      # session has this order id, or is in the middle of creating its order: the webhook can
      # arrive before OrderService has stored the order id.
      def normalize(params, shop = nil)
        return params unless params.is_a?(Hash)

        public_id = note_attribute(params, SESSION_ATTRIBUTE)
        return params if public_id.blank?

        session = find_session(public_id, shop)
        return params if session.nil?
        return params unless created_by_form?(session, params)

        params.merge("source_name" => FORM_SOURCE, "_codk_form" => true)
      rescue StandardError => e
        log_error("normalize", shop, params, e)
        params
      end

      def after(shop, params)
        return unless params.is_a?(Hash)

        public_id = note_attribute(params, SESSION_ATTRIBUTE)
        return if public_id.blank?

        session = find_session(public_id, shop)
        return if session.nil?

        order_id = params["id"].to_s
        if params["_codk_form"]
          remember_order_id(session, order_id)
          sync_cod_fee(params, order_id)
          mark_recovered(shop, session)
        elsif CodForm::Session::HANDOFF_STATUSES.include?(session.status) && session.order_id.blank?
          finish_handoff(shop, session, params, order_id)
        end
      rescue StandardError => e
        log_error("after", shop, params, e)
      end

      def note_attribute(params, name)
        Array(params["note_attributes"]).each do |attribute|
          next unless attribute.is_a?(Hash) && attribute["name"].to_s == name

          return attribute["value"].to_s.strip
        end
        nil
      end

      private

      def find_session(public_id, shop)
        return nil unless public_id.match?(/\A[0-9a-fA-F\-]{16,64}\z/)

        scope = CodForm::Session.where(public_id: public_id)
        scope = scope.where(shop_id: shop.id) if shop
        scope.first
      end

      def created_by_form?(session, params)
        order_id = params["id"].to_s
        return true if session.order_id.present? && session.order_id.to_s == order_id
        return false if session.order_id.present?

        session.status == CodForm::Session::STATUS_ORDERING && params["source_name"].to_s == DRAFT_SOURCE
      end

      # The submit request may die between Shopify creating the order and the session being
      # updated. Leaving the order id here lets a later submit adopt this order instead of
      # creating a second one (CodForm::OrderService#adopt_webhook_order). updated_at is left
      # alone on purpose: it is the staleness clock of the 'ordering' state.
      def remember_order_id(session, order_id)
        return if session.order_id.present? || !order_id.match?(/\A\d+\z/)

        CodForm::Session.where(id: session.id, order_id: nil).update_all(
          ["tracking = jsonb_set(COALESCE(tracking, '{}'::jsonb), '{webhook_order_id}', to_jsonb(?::text), true)", order_id]
        )
      end

      # (a) The job computes OrderConfirmation#cod_fee from Setting; the form order carries the
      # exact fee it charged.
      def sync_cod_fee(params, order_id)
        fee = note_attribute(params, FEE_ATTRIBUTE)
        return if fee.blank?

        confirmation = OrderConfirmation.find_by(order_id: order_id)
        confirmation&.update_columns(cod_fee: fee.to_d)
      end

      # (b) Abandoned-form anchors of this session (and of the session it recovered).
      def mark_recovered(shop, session)
        ids = ["codf_#{session.public_id}"]
        origin = session.tracking.is_a?(Hash) ? session.tracking["recovered_from"].to_s : ""
        ids << "codf_#{origin}" unless origin.empty?
        shop.abandoned_carts.where(checkout_id: ids).update_all(notes: "Recovered", updated_at: Time.current)
      end

      # (c) Partial / prepaid orders that started in the form and were paid at Shopify checkout.
      # Idempotent: the compare-and-set on order_id IS NULL lets exactly one run through.
      def finish_handoff(shop, session, params, order_id)
        partial = session.status == CodForm::Session::STATUS_HANDOFF_PARTIAL
        claimed = CodForm::Session
                  .where(id: session.id, order_id: nil, status: CodForm::Session::HANDOFF_STATUSES)
                  .update_all(
                    status: CodForm::Session::STATUS_ORDERED, order_id: order_id, order_name: params["name"].to_s,
                    order_total_cents: (params["total_price"].to_d * 100).round.to_i,
                    ordered_at: Time.current, updated_at: Time.current
                  )
        return unless claimed == 1

        session.reload
        mark_recovered(shop, session)

        if partial
          %w[codking_form codking_form_partial].each do |tag|
            ShopifyServices::OrderTagPostService.call(shop, order_id, tag)
          rescue StandardError => e
            Rails.logger.warn("[CodForm::OrderWebhookHook] tag failed shop_id=#{shop.id} order_id=#{order_id} #{e.class}")
          end
          CodForm::CapService.record_order!(shop, session, partial: true) unless session.is_test
        end
        store_order_note(session, params)

        # PRE-10 / CAP-1: a partial order is a counted form order, so it gets what every form
        # order gets after creation (Sheets row, CRM event, overage count). A prepaid order is
        # not counted (CAP-1) and gets none of it. The string literal is
        # CodForm::PostOrderJob::ORIGIN_HANDOFF (not referenced, to keep this file loadable alone).
        if partial
          begin
            CodForm::PostOrderJob.perform_async(session.id, "handoff")
          rescue StandardError => e
            Rails.logger.warn("[CodForm::OrderWebhookHook] post-order enqueue failed shop_id=#{shop.id} order_id=#{order_id} #{e.class}")
          end
        end

        CodForm::FunnelLogger.log(
          shop_id: shop.id, session_token: session.public_id,
          type: partial ? "cf_order_created" : "cf_prepaid_order",
          meta: CodForm::QuoteService.funnel_meta(session).merge(
            "partial" => partial, "value_cents" => session.order_total_cents, "currency" => params["currency"].to_s
          )
        )
      end

      # The buyer writes the order note in Shopify checkout for a hand-off order; keep it where
      # the form's own submit keeps it (custom_fields["note"]) so the Sheets `note` column fills.
      # Buyer text: stored only, never logged.
      def store_order_note(session, params)
        note = params["note"].to_s.strip[0, 500]
        return if note.empty?

        fields = session.custom_fields.is_a?(Hash) ? session.custom_fields : {}
        return if fields["note"].to_s.strip != ""

        session.update_columns(custom_fields: fields.merge("note" => note))
      rescue StandardError => e
        Rails.logger.warn("[CodForm::OrderWebhookHook] note not stored shop_id=#{session.shop_id} #{e.class}")
      end

      def log_error(stage, shop, params, error)
        order_id = params.is_a?(Hash) ? params["id"] : nil
        Rails.logger.error(
          "[CodForm::OrderWebhookHook] #{stage} failed shop_id=#{shop&.id} order_id=#{order_id} #{error.class}"
        )
      end
    end
  end
end
