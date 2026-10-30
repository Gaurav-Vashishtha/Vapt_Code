module SidekiqJobs
  # SidekiqJobs::OrdersReport.perform_async
  class OrdersReport < ApplicationJob
    def perform(*args)
      
      recent_ac_success = AbandonedCart.where('updated_at > ?', 4.hours.ago).where(status:'SUCCESS').count
      recent_ac_failed = AbandonedCart.where('updated_at > ?', 4.hours.ago).where.not(status:'SUCCESS').count

      recent_orders = OrderConfirmation.where('created_at > ?', 4.hours.ago)



      shop_wise_stats = recent_orders.where.not(status:'Non-COD').group(:shop_id).group(:status).count
      shop_by_id = {}
      shop_wise_stats_list = []
      shop_wise_stats.each do |stat|
        shop_id=stat.first.first
        if shop_by_id[shop_id].blank?
          shop_by_id[shop_id]=Shop.find(shop_id).shopify_domain
        end
        shop_wise_stats_list.push("#{shop_by_id[shop_id]} - #{stat.first.second} - #{stat.second}")
      end

      verified_orders = recent_orders.where(status: 'COD-Verified').size
      pending_orders = recent_orders.where(status: 'Pending').size
      auto_cancelled_orders = recent_orders.where(status: 'COD-Auto-Cancelled').size
      partial_paid_orders = recent_orders.where(status: 'COD-Partial-Payment-Received').size
      is_max_tried_orders = recent_orders.where(is_max_tried: true).size
      total_cod_orders = verified_orders + pending_orders + auto_cancelled_orders



      if total_cod_orders > 0
        verified_pct = (100 * verified_orders) / total_cod_orders
        pending_pct = (100 * pending_orders) / total_cod_orders
        auto_cancelled_pct = (100 * auto_cancelled_orders) / total_cod_orders
      else
        verified_pct = 0
        pending_pct = 0
      end

      SlackNotifier::CLIENT.ping(
        text: ":sunglasses: *Recent Order Logs* (#{Rails.env})" +
        "\n Verified: *#{verified_pct} %*   (#{verified_orders}) "+ 
        "\nPending: *#{pending_pct} %*   (#{pending_orders}) " +
        "\n Auto_Cancelled: *#{auto_cancelled_pct} %*   (#{auto_cancelled_orders})" + 
        "\n Partial Paid Orders:  #{partial_paid_orders}" +
        "\n Max Tried Orders:  #{is_max_tried_orders}" + 
        "\n Abandoned Cart Success:  #{recent_ac_success}"+ 
        "\n Abandoned Cart Failed:  #{recent_ac_failed}" 
      )
      SlackNotifier::CLIENT.ping(
        text: ":sunglasses: *Recent Order Logs - Shopwise* (#{Rails.env}) \n #{shop_wise_stats_list.join("\n")}",
      )
    end
  end
end