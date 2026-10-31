module NetworkServices
  class PayuLinkService < ApplicationService
    attr_reader :shop, :order_confirmation

    # NetworkServices::PayuLinkService.call(Shop.last, OrderConfirmation.last)
    def initialize(shop, order_confirmation, reminder: nil)
      @shop = shop
      @order_confirmation = order_confirmation
      @reminder = reminder
    end

    def call
      return order_confirmation.prepaid_link unless valid_conditions?

      credentials = Payu::Credentials.for(shop.setting)
      unless credentials.links_ready?
        Rails.logger.error("[PayuLinkService] incomplete PayU credentials for #{shop.shopify_domain}")
        return order_confirmation.order_status_url
      end

      token = Payu::AccessTokenService.call(credentials)
      if token.blank?
        Rails.logger.error("[PayuLinkService] OAuth token blank for #{shop.shopify_domain} (see [payu/oauth] logs above)")
        notify_slack("⚠️ PayU OAuth token fetch failed for order #{order_confirmation.id} (#{shop.shopify_domain})")
        return order_confirmation.order_status_url
      end

      begin
        digest = Digest::MD5.hexdigest(order_confirmation.id.to_s)
        order_confirmation.update(digest: digest)

        discount      = @reminder && @reminder['discount']
        discount_type = @reminder && @reminder['discount_type']
        add_shipping  = !!(@reminder && @reminder['add_shipping'])
        # PayU amounts are in rupees (unlike Razorpay's paise), so no *100.
        amount = ShopifyServices::PrepaidOrderService.new(nil, shop, order_confirmation.id)
                   .get_total_amount(discount: discount, discount_type: discount_type, add_shipping: add_shipping)
        amount = format('%.2f', amount).to_f

        txnid = "CODK#{order_confirmation.id}T#{SecureRandom.hex(4)}"

        body = {
          subAmount: amount,
          isAmountFilledByCustomer: false,
          description: "For payment of #{order_confirmation.order_id} in #{shop.owner_name}",
          source: 'API',
          invoiceNumber: txnid,
          maxPaymentsAllowed: 1,
          expiryDate: (Time.now + shop.setting.prepaid_expiry.to_i.minutes).strftime('%Y-%m-%d %H:%M:%S'),
          successURL: callback_url(digest),
          failureURL: callback_url(digest),
          customer: {
            name: order_confirmation.customer_name,
            email: order_confirmation.customer_email,
            phone: order_confirmation.customer_number
          },
          udf: { udf1: order_confirmation.id.to_s }
        }

        resp = HTTParty.post(
          "#{Payu::Api.oneapi_base}/payment-links",
          body: body.to_json,
          headers: {
            'Content-Type' => 'application/json',
            'Authorization' => "Bearer #{token}",
            'merchantId' => credentials.merchant_id
          },
          timeout: 25
        )

        parsed = JSON.parse(resp.body || '{}') rescue {}
        payment_link = parsed.dig('result', 'paymentLink')

        if resp.success? && payment_link.present?
          cutly_url = NetworkServices::CutlyLinkService.call(payment_link)
          store_txnid(txnid)
          # CALLBACK-RECEIVED makes PrepaidConversionJob poll PayuStatusService
          # until the link is paid, so a missed browser callback still converts.
          order_confirmation.update(prepaid_link: cutly_url, prepaid_status: 'CALLBACK-RECEIVED')
        else
          notify_slack("⚠️ PayU link generation failed for order #{order_confirmation.id} (#{shop.shopify_domain}): #{parsed['message'] || resp.body}")
          Rails.logger.error("[PayuLinkService] link create failed: HTTP #{resp.code} body=#{resp.body.inspect} parsed=#{parsed.inspect}")
          return order_confirmation.order_status_url
        end
      rescue => e
        notify_slack("⚠️ Error generating PayU link for order #{order_confirmation.id} (#{shop.shopify_domain}): #{e.message}")
        Rails.logger.error("[PayuLinkService] Error: #{e.message}")
        return order_confirmation.order_status_url
      end

      order_confirmation.prepaid_link
    end

    private

    def notify_slack(text)
      SlackNotifier::CLIENT.ping(text: text)
    rescue => e
      Rails.logger.warn("[PayuLinkService] slack notify skipped: #{e.message}")
    end

    def callback_url(digest)
      "https://#{ENV.fetch("APP_HOST", nil)}/order/prepaid?digest=#{digest}"
    end

    def store_txnid(txnid)
      existing = order_confirmation.phonepe_transaction_ids.to_s.split(',').map(&:strip).reject(&:blank?)
      existing << txnid
      order_confirmation.update(phonepe_transaction_ids: existing.uniq.join(','))
    end

    # Mirrors RazorpayLinkService: regenerate when a reminder is supplied (its
    # discount may differ), otherwise reuse an existing link.
    def valid_conditions?
      order_confirmation.present? &&
        (order_confirmation.prepaid_link.blank? || @reminder.present?) &&
        shop.setting.payment_provider_api_key.present? &&
        shop.setting.payment_provider_api_secret.present?
    end
  end
end
