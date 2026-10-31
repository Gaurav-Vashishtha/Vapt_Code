module NetworkServices
  class CashfreeLinkService < ApplicationService
    attr_reader :shop, :order_confirmation

    # NetworkServices::CashfreeLinkService.call(Shop.last, OrderConfirmation.last)
    #
    # `reminder` is the resolved per-reminder override hash. When present we
    # regenerate the link even if one already exists, because the reminder's
    # discount may differ from the amount baked into the existing link
    # (mirrors RazorpayLinkService / PayuLinkService).
    def initialize(shop, order_confirmation, reminder: nil)
      @shop = shop
      @order_confirmation = order_confirmation
      @reminder = reminder
    end

    def call
      return order_confirmation.prepaid_link unless valid_conditions?

      credentials = Cashfree::Credentials.for(shop.setting)
      unless credentials.ready?
        Rails.logger.error("[CashfreeLinkService] incomplete Cashfree credentials for #{shop.shopify_domain}")
        return order_confirmation.order_status_url
      end

      begin
        digest = Digest::MD5.hexdigest(order_confirmation.id.to_s)
        order_confirmation.update(digest: digest)

        discount      = @reminder && @reminder['discount']
        discount_type = @reminder && @reminder['discount_type']
        add_shipping  = !!(@reminder && @reminder['add_shipping'])
        # Cashfree amounts are in rupees (like PayU, unlike Razorpay's paise).
        amount = ShopifyServices::PrepaidOrderService.new(nil, shop, order_confirmation.id)
                   .get_total_amount(discount: discount, discount_type: discount_type, add_shipping: add_shipping)
        amount = format('%.2f', amount).to_f

        # link_id: alphanumeric + underscore/hyphen, unique, <=50 chars.
        link_id = "CODK#{order_confirmation.id}T#{SecureRandom.hex(4)}"

        body = {
          link_id: link_id,
          link_amount: amount,
          link_currency: 'INR',
          link_purpose: "For payment of #{order_confirmation.order_id} in #{shop.owner_name}",
          link_partial_payments: false,
          # Expiry computed from Time.now (not created_at) so old orders never
          # get a past expiry, which Cashfree rejects.
          link_expiry_time: (Time.now + shop.setting.prepaid_expiry.to_i.minutes).iso8601,
          link_auto_reminders: false,
          customer_details: {
            customer_name: order_confirmation.customer_name,
            customer_email: order_confirmation.customer_email,
            customer_phone: order_confirmation.customer_number
          },
          link_notify: {
            send_sms: false,
            send_email: false
          },
          link_meta: {
            return_url: callback_url(digest)
          },
          link_notes: {
            order_confirmation_id: order_confirmation.id.to_s
          }
        }

        resp = HTTParty.post(
          "#{Cashfree::Api.pg_base}/links",
          body: body.to_json,
          headers: credentials.headers,
          timeout: 25
        )

        parsed = JSON.parse(resp.body || '{}') rescue {}
        payment_link = parsed['link_url']

        if resp.success? && payment_link.present?
          cutly_url = NetworkServices::CutlyLinkService.call(payment_link)
          store_txnid(link_id)
          # CALLBACK-RECEIVED makes PrepaidConversionJob poll CashfreeStatusService
          # until the link is paid, so a missed browser callback still converts.
          order_confirmation.update(prepaid_link: cutly_url, prepaid_status: 'CALLBACK-RECEIVED')
        else
          notify_slack("⚠️ Cashfree link generation failed for order #{order_confirmation.id} (#{shop.shopify_domain}): #{parsed['message'] || resp.body}")
          Rails.logger.error("[CashfreeLinkService] link create failed: HTTP #{resp.code} body=#{resp.body.inspect} parsed=#{parsed.inspect}")
          return order_confirmation.order_status_url
        end
      rescue => e
        notify_slack("⚠️ Error generating Cashfree link for order #{order_confirmation.id} (#{shop.shopify_domain}): #{e.message}")
        Rails.logger.error("[CashfreeLinkService] Error: #{e.message}")
        return order_confirmation.order_status_url
      end

      order_confirmation.prepaid_link
    end

    private

    def notify_slack(text)
      SlackNotifier::CLIENT.ping(text: text)
    rescue => e
      Rails.logger.warn("[CashfreeLinkService] slack notify skipped: #{e.message}")
    end

    def callback_url(digest)
      "https://#{ENV.fetch("APP_HOST", nil)}/order/prepaid?digest=#{digest}"
    end

    # Store the Cashfree link_id in phonepe_transaction_ids (the shared
    # non-Razorpay ref column). It must NOT go in payment_link_id — the
    # reconciliation jobs treat payment_link_id.present? as "this is Razorpay".
    def store_txnid(txnid)
      existing = order_confirmation.phonepe_transaction_ids.to_s.split(',').map(&:strip).reject(&:blank?)
      existing << txnid
      order_confirmation.update(phonepe_transaction_ids: existing.uniq.join(','))
    end

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
