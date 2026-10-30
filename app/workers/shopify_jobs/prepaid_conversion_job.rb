module ShopifyJobs
  class PrepaidConversionJob < ApplicationJob

    LOOK_BACK_DAYS = 1

    def perform
      puts 'CodPrepaidJob job started'
      scanned_orders = 0
      failed_orders = 0
      success_orders = 0

      order_confirmations = OrderConfirmation
        .where('created_at > ?', Time.now - LOOK_BACK_DAYS.days)
        .where(prepaid_status: 'CALLBACK-RECEIVED')

      order_confirmations.each do |order_confirmation|
        begin
          scanned_orders += 1

          if order_confirmation.payment_link_id.present?
            Razorpay.setup(
              order_confirmation.shop.setting.payment_provider_api_key,
              order_confirmation.shop.setting.payment_provider_api_secret
            )
            Razorpay.headers = { "Content-type" => "application/json" }

            resp = Razorpay::PaymentLink.fetch(order_confirmation.payment_link_id)

            if resp.present? && resp.status == 'paid'
              prepaid_resp = ShopifyServices::PrepaidOrderService.call(order_confirmation.shop, order_confirmation.id)
              success_orders += 1 if prepaid_resp.present?
            elsif resp.present?
              order_confirmation.update(prepaid_status: "RazorPayResponse-#{resp.status}")
            end

          elsif order_confirmation.shop.setting.payment_provider == 'PHONEPE'
            if NetworkServices::PhonepeStatusService.call(order_confirmation.shop, order_confirmation)
              prepaid_resp = ShopifyServices::PrepaidOrderService.call(order_confirmation.shop, order_confirmation.id)
              success_orders += 1 if prepaid_resp.present?
            else
              SlackNotifier::CLIENT.ping(
                text: "Phonepe false callback received (#{Rails.env}) - #{order_confirmation.id} - #{order_confirmation.shop.shopify_domain}"
              )
              order_confirmation.update(prepaid_status: 'Phonepe false callback received')
            end

          elsif order_confirmation.shop.setting.payment_provider == 'PAYMOB'
            if NetworkServices::PaymobStatusService.call(order_confirmation.shop, order_confirmation)
              prepaid_resp = ShopifyServices::PrepaidOrderService.call(order_confirmation.shop, order_confirmation.id)
              success_orders += 1 if prepaid_resp.present?
            else
              # SlackNotifier::CLIENT.ping(
              #   text: "Paymob false callback received (#{Rails.env}) - #{order_confirmation.id} - #{order_confirmation.shop.shopify_domain}"
              # )
              # order_confirmation.update(prepaid_status: 'Paymob false callback received')
              puts "false callback received"
            end

          elsif order_confirmation.shop.setting.payment_provider == 'GE_IDEA'
            if NetworkServices::GeideaStatusService.call(order_confirmation.shop, order_confirmation)
              prepaid_resp = ShopifyServices::PrepaidOrderService.call(order_confirmation.shop, order_confirmation.id)
              success_orders += 1 if prepaid_resp.present?
            else
              puts "Geidea false callback received"
            end

          elsif order_confirmation.shop.setting.payment_provider == 'PAYU'
            if NetworkServices::PayuStatusService.call(order_confirmation.shop, order_confirmation)
              prepaid_resp = ShopifyServices::PrepaidOrderService.call(order_confirmation.shop, order_confirmation.id)
              success_orders += 1 if prepaid_resp.present?
            else
              puts "PayU false callback received"
            end

          elsif order_confirmation.shop.setting.payment_provider == 'CASHFREE'
            if NetworkServices::CashfreeStatusService.call(order_confirmation.shop, order_confirmation)
              prepaid_resp = ShopifyServices::PrepaidOrderService.call(order_confirmation.shop, order_confirmation.id)
              success_orders += 1 if prepaid_resp.present?
            else
              puts "Cashfree false callback received"
            end
          end

        rescue => e
          SlackNotifier::CLIENT.ping(
            text: "Error processing COD to prepaid (#{Rails.env}) - #{order_confirmation.id} - #{order_confirmation.shop.shopify_domain} #{e.message} #payment Link #{order_confirmation.prepaid_link}"
          )
          failed_orders += 1
        end
      end

      if success_orders > 0 || failed_orders > 0
        SlackNotifier::CLIENT.ping(
          text: "Report for COD-Prepaid Job (#{Rails.env}) - Scanned Orders #{scanned_orders} - Success Orders #{success_orders} - Failed Orders #{failed_orders}"
        )
      end

      puts 'CodPrepaidJob job completed'
    end
  end
end
