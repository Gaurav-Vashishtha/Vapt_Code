require "razorpay"

module NetworkServices
  class RazorpayLinkService < ApplicationService
    attr_reader :shop, :order_confirmation

    # Usage:
    # NetworkServices::RazorpayLinkService.call(Shop.last, OrderConfirmation.last)

    # `reminder` is the resolved per-reminder override hash (from
    # Setting#resolve_prepaid_reminder). When present, we regenerate the
    # Razorpay link even if one already exists, because the reminder's
    # discount may differ from the one baked into the existing link.
    def initialize(shop, order_confirmation, reminder: nil)
      @shop = shop
      @order_confirmation = order_confirmation
      @reminder = reminder
    end

    def call
      return order_confirmation.prepaid_link unless valid_conditions?

      begin
        digest = Digest::MD5.hexdigest(order_confirmation.id.to_s)
        order_confirmation.update(digest: digest)

        Razorpay.setup(shop.setting.payment_provider_api_key, shop.setting.payment_provider_api_secret)
        Razorpay.headers = { "Content-type" => "application/json" }

        discount      = @reminder && @reminder['discount']
        discount_type = @reminder && @reminder['discount_type']
        add_shipping  = !!(@reminder && @reminder['add_shipping'])
        order_amount = (ShopifyServices::PrepaidOrderService.new(nil, shop, order_confirmation.id)
                          .get_total_amount(discount: discount, discount_type: discount_type, add_shipping: add_shipping) * 100).to_i

        params = {
          amount: order_amount,
          currency: "INR",
          expire_by: (order_confirmation.created_at.to_i + shop.setting.prepaid_expiry * 60),
          accept_partial: false,
          description: "For payment of #{order_confirmation.order_id} in #{shop.owner_name}",
          customer: {
            name: order_confirmation.customer_name,
            email: order_confirmation.customer_email,
            contact: order_confirmation.customer_number
          },
          notify: {
            sms: false,
            email: false
          },
          reminder_enable: shop.setting.prepaid_notif,
          notes: {
            policy_name: "Order payment"
          },
          callback_url: "https://#{ENV.fetch("APP_HOST", nil)}/order/prepaid?digest=#{digest}",
          callback_method: "get"
        }

        resp = Razorpay::PaymentLink.create(params.to_json)
        cutly_url = NetworkServices::CutlyLinkService.call(resp.short_url)
        order_confirmation.update(prepaid_link: cutly_url, payment_link_id: resp.id)

      rescue => e
        SlackNotifier::CLIENT.ping(
          text: "⚠️ Error generating Razorpay link for order ID #{order_confirmation.id} (Shop: #{shop.shopify_domain}): #{e.message}"
        )
        Rails.logger.error("[RazorpayLinkService] Error: #{e.message}}")
        return order_confirmation.order_status_url
      end

      order_confirmation.prepaid_link
    end

    private

    # When a reminder is supplied we ALWAYS regenerate, because each reminder
    # carries its own discount and the previous link's amount may no longer be
    # right. Legacy callers (reminder nil) keep the existing reuse behavior.
    def valid_conditions?
      order_confirmation.present? &&
        (order_confirmation.prepaid_link.blank? || @reminder.present?) &&
        shop.setting.payment_provider_api_key.present? &&
        shop.setting.payment_provider_api_secret.present?
    end
  end
end
