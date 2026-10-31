module NetworkJobs
  # NetworkJobs::FirstPurchaseScheduleJob.perform_async(Shop.last.id,OrderConfirmation.last.id)
  class FirstPurchaseScheduleJob < ApplicationJob
    def perform(shop_id, order_confirmation_id)
      shop = Shop.find(shop_id)
      if shop.setting.locked 
        return
      end
      if (!shop.blank?) && shop.setting.first_purchase_whatsapp_enabled
        order_confirmation = OrderConfirmation.find(order_confirmation_id)
        params = ShopifyServices::OrderFullGetService.call(
            shop,
            order_confirmation.order_id
          )
          # params is nil whenever Shopify was unreadable (dead token, deleted
          # order). Fall back to the orders we hold for this customer rather
          # than dying on nil, and skip entirely when even that is unavailable
          # — better no message than a "first purchase" greeting to a repeat
          # buyer.
          numberOfOrders = params&.dig('customer','numberOfOrders')
          numberOfOrders = numberOfOrders.present? ? numberOfOrders.to_i : local_orders_count(shop, order_confirmation)
          if numberOfOrders.blank?
            Rails.logger.warn(
              "[first_purchase] cannot determine order count shop=#{shop.shopify_domain} order=#{order_confirmation.order_id} — skipping"
            )
            return
          end
          if numberOfOrders <= 1
            # Schedule it according to configuration.
            if !shop.setting.first_purchase_schedule.blank?
              shop.setting.first_purchase_schedule.split(",").each do|schedule|
                mins = schedule.to_i                
                  NetworkJobs::SendFirstPurchaseNotifJob.perform_in( mins*(1.minutes), shop.id,order_confirmation.id)
              end
            else
              NetworkJobs::SendFirstPurchaseNotifJob.perform_async(shop.id,order_confirmation.id)
            end
          end
      else
        return
      end
    end

    # Lower bound on how many orders this customer has placed with this shop,
    # from our own records — exactly what the `<= 1` first-purchase test needs:
    # if we already hold two orders for the number, it isn't their first.
    # nil when there's no phone number to count by.
    def local_orders_count(shop, order_confirmation)
      number = order_confirmation.customer_number
      return nil if number.blank?

      shop.order_confirmations.where(customer_number: number).count
    rescue StandardError => e
      Rails.logger.warn("[first_purchase] local order count failed shop=#{shop&.id}: #{e.class}: #{e.message}")
      nil
    end
  end
end

