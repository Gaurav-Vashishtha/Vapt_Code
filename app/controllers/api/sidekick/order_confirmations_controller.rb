# frozen_string_literal: true

module Api
  module Sidekick
    class OrderConfirmationsController < BaseController
      # Friendly filter values exposed to Sidekick (tools.json enum) mapped to
      # the raw OrderConfirmation#status strings they cover.
      STATUS_GROUPS = {
        'verified' => %w[COD-Verified COD-Manual-Verified],
        'pending' => %w[Pending],
        'cancelled' => %w[COD-Cancelled COD-Auto-Cancelled COD-Auto-Deleted],
        'converted_to_prepaid' => %w[COD-Prepaid],
        'partial_payment_received' => %w[COD-Partial-Payment-Received],
        'skipped' => %w[COD-SKIP-VERIFICATION COD-SKIP-CANCELLATION Partial-Payment-Order-Skipped]
      }.freeze

      HIDDEN_STATUSES = %w[Test-Order Non-COD].freeze

      def search
        scope = @shop.order_confirmations.where.not(status: HIDDEN_STATUSES).order(created_at: :desc)

        if params[:status].present?
          key = params[:status].to_s.strip.downcase
          scope = scope.where(status: STATUS_GROUPS.fetch(key) { [params[:status].to_s] })
        end

        if params[:query].present?
          term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip.delete_prefix('#'))}%"
          scope = scope.where(
            'order_number ILIKE :t OR customer_number ILIKE :t OR customer_name ILIKE :t OR order_id ILIKE :t',
            t: term
          )
        end

        scope = scope.where(created_at: window_days(default: 90, max: 365).days.ago..) if params[:days].present?

        render json: { results: scope.limit(result_limit).map { |oc| order_link(oc) } }
      end

      private

      def order_link(oc)
        resource_link(
          type: 'order_confirmation',
          id: oc.order_id,
          name: "Order #{oc.order_number.presence || oc.order_id} — #{friendly_status(oc.status)}",
          meta: {
            status: friendly_status(oc.status),
            raw_status: oc.status,
            order_name: oc.order_number,
            customer: oc.customer_name.presence,
            phone: oc.customer_number,
            amount: [oc.currency, oc.order_amount].reject(&:blank?).join(' ').presence,
            partial_payment: oc.partial_payment_variants.present? || nil,
            shipping_status: oc.shipping_status.presence,
            created_at: oc.created_at&.iso8601
          }
        )
      end

      def friendly_status(raw)
        STATUS_GROUPS.find { |_key, values| values.include?(raw) }&.first || raw
      end
    end
  end
end
