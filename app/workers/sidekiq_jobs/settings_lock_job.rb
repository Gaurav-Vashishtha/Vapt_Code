module SidekiqJobs
  class SettingsLockJob < ApplicationJob
    def perform(*args)
      locked = []
      email_count = 0
      Shop.where(charge_id: [nil, '']).each do |shop|
        if shop.order_confirmations.where.not(status: 'Non-COD').size > 3 && (!shop.setting.locked)
          attrs = { locked: true, sms: false, ivr: false, status: false, cod_fee_enabled: false, abandoned_cart_enabled: false, enable_fulfilment_message: false, confirmation_sms_enabled: false }
          wallet = Wallet.find_by(shopify_domain: shop.shopify_domain)
          if wallet.present? && (wallet.total_balance.to_f - wallet.balance_used.to_f) < 1.0
            attrs[:partial_payment_enabled] = false
          end
          shop.setting.update(attrs)
          WelcomeMailer.lock_shop(shop.id).deliver_later
          locked.push(shop.shopify_domain)
          email_count = email_count + 1
        end
      end

      Setting.where(cod_fee_enabled:true).or(Setting.where('enable_shipping_cod_fees':true)).each do |setting|
        shop=setting.shop
        if setting.shop.plan_id == 1 && setting.shop.id > 817 #As older shops should work on free plan.
          order_count = setting.shop.order_confirmations.count
          if order_count > 10 && shop.reminder_count<3 
            WelcomeMailer.will_lock_cod_fee_feature(shop.id).deliver_later
            shop.update(reminder_count:(shop.reminder_count+1))
            email_count=email_count+1
          elsif order_count > 10 && (!shop.setting.lock_paid_feature)
            shop.setting.update({cod_fee_enabled:false, lock_paid_feature:true})
            
            resp = ShopifyServices::PaymentCustomizationService.call(shop , '')
            if resp.blank?
              SlackNotifier::CLIENT.ping(
                text: "Error refreshing meta fields while locking the shop - #{shop.shopify_domain}",
              )
            end
            WelcomeMailer.lock_cod_fee_feature(shop.id).deliver_later
            locked.push(shop.shopify_domain)
            email_count=email_count+1
          end
        end
      end

      # Shop.where(reviewed: [nil, false]).each do |shop|
      #   if !shop.setting.locked and shop.order_confirmations.where.not(status: 'Non-COD').size > 9
      #     shop.setting.update({locked: true, sms: false, ivr: false, status: false})
      #     locked.push(shop.shopify_domain)
      #   end
      # end

      if locked.length > 0
        locked_shops = locked.uniq.join("\n")
        SlackNotifier::CLIENT.ping(
          text: ":sunglasses: *Locked Shops* (#{Rails.env}) \n #{locked_shops} Email Notifications sent #{email_count}",
        )
      end
      
    end
  end
end