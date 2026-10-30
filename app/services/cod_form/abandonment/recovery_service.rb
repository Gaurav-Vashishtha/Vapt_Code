# frozen_string_literal: true

module CodForm
  module Abandonment
    # Recovery of an abandoned form (ARCHITECTURE.md I.4, ABN-2).
    #
    #   RecoveryService.prefill(shop, recovery_token) -> Hash | nil       (K.9, used by the session endpoint)
    #     {"contact","address","items","discount"} (D.1 `prefill`) plus "recovered_from" =>
    #     the abandoned session's public id, which the session endpoint stores in the new
    #     session's tracking["recovered_from"].
    #   RecoveryService.complete!(shop, session) -> Integer                (called by PostOrderJob)
    #     After an order: the abandoned session(s) this order recovers become `recovered` and
    #     their anchors get notes = 'Recovered'.
    class RecoveryService
      MAX_AGE = 30.days

      class << self
        def prefill(shop, recovery_token)
          token = recovery_token.to_s
          return nil unless token.match?(/\A[A-Za-z0-9_-]{16,64}\z/)

          session = CodForm::Session.find_by(shop_id: shop.id, recovery_token: token)
          return nil if session.nil? || session.status != CodForm::Session::STATUS_ABANDONED
          return nil if session.abandoned_at.nil? || session.abandoned_at < MAX_AGE.ago

          general = CodForm::ShopConfig.for(shop).general
          abandonment = general.is_a?(Hash) && general["abandonment"].is_a?(Hash) ? general["abandonment"] : {}
          data = CodForm::Engine::Recovery.prefill(
            session: session.attributes.slice("contact", "address", "cart_snapshot"),
            recovery_discount: abandonment["recovery_discount"]
          )
          data.merge("recovered_from" => session.public_id)
        rescue StandardError => e
          Rails.logger.warn("[codf/recovery] prefill failed shop=#{shop&.id} #{e.class}")
          nil
        end

        # session: the session that just produced an order. Recovers
        #   - the session named in tracking["recovered_from"] (opened from a recovery link), and
        #   - abandoned sessions of the same shop and the same phone / email in the last 30 days
        #     (the buyer came back on their own).
        def complete!(shop, session)
          return 0 if session.order_id.blank?

          scope = CodForm::Session.where(shop_id: shop.id, status: CodForm::Session::STATUS_ABANDONED)
                                  .where.not(id: session.id)
                                  .where("abandoned_at >= ?", MAX_AGE.ago)
          origin = session.tracking.is_a?(Hash) ? session.tracking["recovered_from"].to_s : ""
          matches = []
          matches.concat(scope.where(public_id: origin).to_a) if origin.match?(/\A[0-9a-fA-F-]{16,64}\z/)
          matches.concat(scope.where(phone_normalized: session.phone_normalized).to_a) if session.phone_normalized.present?
          matches.concat(scope.where(email_normalized: session.email_normalized).to_a) if session.email_normalized.present?
          matches.uniq!(&:id)
          return 0 if matches.empty?

          now = Time.current
          CodForm::Session.where(id: matches.map(&:id), status: CodForm::Session::STATUS_ABANDONED)
                          .update_all(status: CodForm::Session::STATUS_RECOVERED, recovered_at: now, updated_at: now)
          checkout_ids = matches.map { |row| MarkAbandonedService.anchor_checkout_id(row.public_id) }
          shop.abandoned_carts.where(checkout_id: checkout_ids)
              .where("lower(coalesce(notes, '')) <> 'recovered'")
              .update_all(notes: "Recovered", updated_at: now)
          matches.size
        end
      end
    end
  end
end
