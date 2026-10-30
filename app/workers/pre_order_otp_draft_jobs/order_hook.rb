# frozen_string_literal: true

module PreOrderOtpDraftJobs
  # Called from OrderConfirmationCreateJob for every order webhook. Cheap DB lookups only;
  # Shopify calls happen in CleanupJob. Never raises into the order flow.
  #
  #  - Order is the merchant completing one of our drafts (_codkAbandonedDraft attribute):
  #    mark the draft completed, the OTP session ORDER_PLACED and its reminders Recovered.
  #  - Any other order for the same session (_codkSessionId) or verified phone
  #    (_otpVerifiedPhoneNumber): delete the open draft(s) via CleanupJob.
  module OrderHook
    module_function

    def call(shop, params)
      attrs = Array(params["note_attributes"]).each_with_object({}) do |a, h|
        h[a["name"].to_s] = a["value"].to_s if a.respond_to?(:[])
      end
      order_id = params["id"].to_s

      if (draft_row_id = attrs[PreOrderOtpDraftOrder::DRAFT_ATTRIBUTE]).present?
        completed_from_draft(shop, draft_row_id, order_id)
        return
      end

      session_id = attrs["_codkSessionId"].presence
      phone_digits = PreOrderOtpDraftOrder.digits(attrs["_otpVerifiedPhoneNumber"])
      return if session_id.blank? && phone_digits.blank?

      scope = PreOrderOtpDraftOrder.open_drafts.where(shop_id: shop.id)
      by_session = session_id && scope.where(device_id: session_id)
      by_phone = phone_digits && scope.where(phone_digits: phone_digits)
      rows = by_session && by_phone ? by_session.or(by_phone) : (by_session || by_phone)
      rows.pluck(:id).each { |id| CleanupJob.perform_async(id, order_id) }
    rescue StandardError => e
      Rails.logger.error("[otp_draft_order] order hook failed shop=#{shop&.id} order=#{params['id']}: #{e.class} #{e.message}")
    end

    def completed_from_draft(shop, draft_row_id, order_id)
      row = PreOrderOtpDraftOrder.find_by(id: draft_row_id, shop_id: shop.id)
      return if row.blank?

      row.update!(status: "completed", shopify_order_id: order_id)

      otps = PreOrderOtp.where(shop_id: shop.id, device_id: row.device_id)
      otps.find_each do |otp|
        ids = otp.shopify_order_ids.to_s.split(",").map(&:strip).reject(&:blank?)
        otp.update(order_status: "ORDER_PLACED", shopify_order_ids: (ids | [order_id]).join(","))
      end
      # Same Recovered marking OrderConfirmationCreateJob does for OTP orders, so reminders stop.
      shop.abandoned_carts
          .where(checkout_id: [row.device_id] + otps.pluck(:id).map { |id| "otp_#{id}" })
          .update_all(notes: "Recovered")
    end
  end
end
