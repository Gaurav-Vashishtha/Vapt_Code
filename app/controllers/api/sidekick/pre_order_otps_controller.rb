# frozen_string_literal: true

module Api
  module Sidekick
    class PreOrderOtpsController < BaseController
      # Friendly filter values (tools.json enum) -> raw verification_status.
      STATUS_GROUPS = {
        'verified' => %w[VERIFIED OTP-Verified],
        'pending' => ['', nil, 'PENDING']
      }.freeze

      def search
        scope = @shop.pre_order_otps.otp_sends.order(created_at: :desc)

        if params[:status].present?
          key = params[:status].to_s.strip.downcase
          scope = scope.where(verification_status: STATUS_GROUPS.fetch(key) { [params[:status].to_s] })
        end

        if params[:query].present?
          term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip)}%"
          scope = scope.where('phone ILIKE :t OR shopify_order_ids ILIKE :t', t: term)
        end

        render json: { results: scope.limit(result_limit).map { |otp| otp_link(otp) } }
      end

      private

      def otp_link(otp)
        verified = STATUS_GROUPS['verified'].include?(otp.verification_status)

        resource_link(
          type: 'pre_order_otp',
          id: otp.id,
          name: "Pre-order OTP #{otp.phone} — #{verified ? 'verified' : 'not verified'}",
          meta: {
            phone: otp.phone,
            verified: verified,
            raw_verification_status: otp.verification_status.presence,
            order_status: otp.order_status,
            channel: otp.ver_type.presence,
            charged: otp.is_charged,
            created_at: otp.created_at&.iso8601
          }
        )
      end
    end
  end
end
