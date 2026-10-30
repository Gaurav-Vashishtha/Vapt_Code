module ShopifyJobs
  class AutoVerifyJob < ApplicationJob

    LOOK_BACK_DAYS = 1
    def perform
      puts 'Retry job started'
      shop_ids = ENV['AUTO_VERIFY_SHOPS'].split(",")
      shop_ids.each do |shop_id|
        Shop.find(shop_id).order_confirmations.where(status:'Pending').
                          where('created_at < ?', Time.now-15.minutes).
                          where('created_at > ?', Time.now-LOOK_BACK_DAYS.days).
        each_with_index do |order_confirmation, index|
          if index!=0 && (index%9!=0 && index%7!=0) && !order_confirmation.customer_number.blank? && !order_confirmation.order_amount.blank? && order_confirmation.order_amount.to_i > 0 
            order_confirmation.update(status: 'COD-Verified', confirmed_at: Time.new)
            ShopifyJobs::OrderPostJob.perform_async(
                      order_confirmation.shop.id,
                      order_confirmation.id
            )
            puts "OrderID is confirmed #{order_confirmation.order_id}" 
          end
        end
      end
    end
  end
end
