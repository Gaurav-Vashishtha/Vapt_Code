# frozen_string_literal: true

module Api
  module Sidekick
    # Abandoned cart recovery results. Rows are one per reminder send; anchor
    # rows are ingest records for webhook-sourced carts, not sends.
    class AbandonedCartsController < BaseController
      def show
        days = window_days
        payload = cached('abandoned_carts') do
          scope = @shop.abandoned_carts.where(created_at: days.days.ago..)
          sends = scope.where(is_anchor: false)
          recovered = scope.where("lower(coalesce(notes, '')) = 'recovered'")

          {
            days: days,
            carts: scope.distinct.count(:checkout_id),
            reminders_sent: sends.count,
            reminders_by_channel: sends.group('upper(notif_type)').count,
            recovered_carts: recovered.distinct.count(:checkout_id),
            recovered_value: recovered.sum(:total_price).to_f.round(2),
            currency: @shop.currency
          }
        end

        recent = @shop.abandoned_carts.where(is_anchor: false).order(created_at: :desc).limit(result_limit)

        render json: {
          summary: payload,
          results: recent.map { |cart| cart_link(cart) }
        }
      end

      private

      def cart_link(cart)
        status, error = twilio_status(cart.status)
        resource_link(
          type: 'abandoned_cart',
          id: cart.id,
          name: "Cart #{cart.name.presence || cart.checkout_id} — #{cart.recovered? ? 'recovered' : 'not recovered'}",
          meta: {
            phone: cart.phone,
            total_price: cart.total_price,
            channel: cart.notif_type,
            reminder_status: status,
            reminder_error: error,
            recovered: cart.recovered?,
            created_at: cart.created_at&.iso8601
          }
        )
      end
    end
  end
end
