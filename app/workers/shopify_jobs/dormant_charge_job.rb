module ShopifyJobs
  class DormantChargeJob < ApplicationJob
    
    def perform
      puts 'Dormant job started'
      messages = ''
      total = 0.0;
      exclude_domains = ['078e61-2.myshopify.com','shady-duds.myshopify.com']
      free_shops = Shop.where('created_at < ?',15.day.ago).where(plan_id:1)
      
      free_shops.each do |shop|
       begin 
       order_count =  shop.order_confirmations.where('created_at > ?', 30.day.ago).count
       if order_count < 20 && (!shop.charge_id.blank?)
        shop.init_session
        usage_charge = ShopifyAPI::UsageCharge.new(
        recurring_application_charge_id: shop.charge_id,
        usage_charge: {
          description: "COD-King-OTP-Credits",
          price: 0.79,
        })
        if usage_charge.save
          total = total + 0.79
          messages = messages + " \n Shop  #{shop.shopify_domain} charge #{usage_charge.price}"
        end
       end
      rescue Exception => e
        puts "Exception  #{shop.shopify_domain}"
      end
      end
      SlackNotifier::CLIENT.ping(
        text: "Dormant Shop report (#{Rails.env}) -  #{messages} Total charges #{total}",
      )
    end

  end
end
