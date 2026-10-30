# frozen_string_literal: true

module PreOrderOtpDraftJobs
  # Turns one abandoned pre-order OTP cart session (shop + device_id) into a Shopify draft order,
  # whether or not the shopper finished OTP verification.
  # Enqueued by AdminJobs::PreOrderOtpAbandonmentJob for shops with
  # additional_settings.pre_order_otp_draft_orders on.
  #
  # Duplicate handling:
  #   - one PreOrderOtpDraftOrder row per (shop_id, device_id) (unique index); concurrent jobs
  #     serialise on the row lock and the second sees the fingerprint already applied
  #   - unchanged cart (same fingerprint) on an open draft -> no Shopify call
  #   - changed cart -> draftOrderUpdate on the same draft
  #   - same OTP-verified phone with an open draft from another device in the last 24h -> that draft
  #     is reused (moved to this device) instead of creating a second one
  class SyncJob < ApplicationJob
    sidekiq_options queue: "low", retry: 3

    def perform(shop_id, device_id)
      return if device_id.blank?

      shop = Shop.find_by(id: shop_id)
      return if shop.blank? || !AdditionalSetting.pre_order_otp_draft_orders?(shop.id)

      otps = PreOrderOtp.where(shop_id: shop.id, device_id: device_id)
      # The cart-update endpoint resets every row of the device to IN_PROGRESS, so any
      # ORDER_PLACED row means the current cart was already ordered.
      return log(shop, device_id, "skipped: order already placed") if otps.where(order_status: "ORDER_PLACED").exists?
      return log(shop, device_id, "skipped: not abandoned") unless otps.where(order_status: "AbandonedCheckout").exists?

      # Every abandoned cart gets a draft, verified or not. The newest row is the number the shopper
      # entered last; a verified row on the device wins over it.
      otp = otps.where(verification_status: PreOrderOtpDraftOrder::VERIFIED_OTP_STATUSES).order(updated_at: :desc).first ||
            otps.order(created_at: :desc).first
      verified = PreOrderOtpDraftOrder::VERIFIED_OTP_STATUSES.include?(otp.verification_status)

      line_items = PreOrderOtpCart.line_items(otp.cart_details)
      return log(shop, device_id, "skipped: empty cart") if line_items.empty?

      phone_digits = PreOrderOtpDraftOrder.digits(otp.phone)
      fingerprint = PreOrderOtpCart.fingerprint(line_items)
      # Only a verified number may pick up another device's draft: an unverified one could be
      # someone else's number and would overwrite their draft.
      row = reserve_row(shop, device_id, verified ? phone_digits : nil)

      row.with_lock do
        if row.open_draft? && row.cart_fingerprint == fingerprint
          log(shop, device_id, "skipped: draft #{row.draft_order_name} already matches cart")
          next
        end

        sync(shop, row, otp, line_items, phone_digits, fingerprint, verified)
      end
    end

    private

    def reserve_row(shop, device_id, phone_digits)
      scope = PreOrderOtpDraftOrder.where(shop_id: shop.id)
      row = scope.find_by(device_id: device_id)
      return row if row

      if phone_digits.present?
        same_shopper = scope.open_drafts
                            .where(phone_digits: phone_digits)
                            .where("updated_at > ?", PreOrderOtpDraftOrder::PHONE_REUSE_WINDOW.ago)
                            .order(updated_at: :desc)
                            .first
        if same_shopper
          same_shopper.update!(device_id: device_id)
          return same_shopper
        end
      end

      scope.create!(device_id: device_id, phone_digits: phone_digits, status: "pending")
    rescue ActiveRecord::RecordNotUnique
      scope.find_by!(device_id: device_id)
    end

    def sync(shop, row, otp, line_items, phone_digits, fingerprint, verified)
      svc = ShopifyServices::OtpDraftOrderService.for(shop)
      input = draft_input(svc, row, line_items, phone_digits, verified)

      result = nil
      if row.open_draft?
        result = svc.update(row.draft_order_gid, input)
        # Merchant deleted or completed the draft meanwhile -> start a fresh one.
        result = nil unless result.ok? || draft_still_open?(svc, row)
        action = "updated"
      end
      if result.nil?
        result = with_contact_fallback(input) { |i| svc.create(i) }
        action = "created"
      end

      if result.ok?
        row.update!(status: action, draft_order_gid: result.gid, draft_order_name: result.name,
                    cart_fingerprint: fingerprint, pre_order_otp_id: otp.id, phone_digits: phone_digits,
                    shopify_order_id: nil, last_error: nil)
        log(shop, row.device_id, "#{action} #{result.name}")
        # Order landed while we were talking to Shopify (the order hook saw no open draft yet).
        if PreOrderOtp.where(shop_id: shop.id, device_id: row.device_id, order_status: "ORDER_PLACED").exists?
          CleanupJob.perform_in(15, row.id, nil)
        end
      else
        row.update!(status: row.open_draft? ? row.status : "failed", last_error: result.errors.to_json.first(2000))
        log(shop, row.device_id, "failed: #{result.errors.inspect}")
      end
    end

    def draft_still_open?(svc, row)
      %w[OPEN INVOICE_SENT].include?(svc.status(row.draft_order_gid).status)
    end

    # An invalid phone/email on the draft must not lose the whole draft: retry once without it.
    def with_contact_fallback(input)
      result = yield(input)
      return result if result.ok?
      return result unless result.errors.any? { |e| e[:field].to_s =~ /phone|email/i }

      yield(input.except(:phone, :email))
    end

    # An unverified number is never matched to a Shopify customer or our customers table: if it's
    # mistyped or someone else's, the draft would land on a stranger's account with their address.
    def draft_input(svc, row, line_items, phone_digits, verified)
      customer = verified ? svc.find_customer(phone_digits) : nil
      local = verified && phone_digits ? Customer.where(phone: "+#{phone_digits}").order(updated_at: :desc).first : nil

      name = [customer&.first_name, customer&.last_name].compact_blank.join(" ").presence ||
             [local&.first_name, local&.last_name].map { |v| v.to_s.strip }.compact_blank.join(" ").presence
      email = Customer.real_email(customer&.email) || Customer.real_email(local&.email)

      input = {
        lineItems: line_items.map { |li| { variantId: "gid://shopify/ProductVariant/#{li[:variant_id]}", quantity: li[:quantity].to_i } },
        tags: [PreOrderOtpDraftOrder::TAG, verified ? "otp-verified" : "otp-unverified"],
        note: ["Abandoned COD King pre-order OTP cart", name && "Customer: #{name}",
               phone_digits && "Phone: +#{phone_digits} (#{verified ? 'OTP verified' : 'not verified'})"].compact.join("\n"),
        customAttributes: [
          { key: "_codkSessionId", value: row.device_id.to_s },
          { key: PreOrderOtpDraftOrder::DRAFT_ATTRIBUTE, value: row.id.to_s }
        ]
      }
      input[:phone] = "+#{phone_digits}" if phone_digits
      if customer
        input[:purchasingEntity] = { customerId: customer.id }
        input[:useCustomerDefaultAddress] = true
      elsif email
        input[:email] = email
      end
      input
    end

    def log(shop, device_id, message)
      Rails.logger.info("[otp_draft_order] shop=#{shop.id} device=#{device_id} #{message}")
    end
  end
end
