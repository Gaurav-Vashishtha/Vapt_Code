module ShopifyJobs
  class AutoCancelJob < ApplicationJob
    
    LOOK_BACK_DAYS = 1
    
    def perform
      puts 'Auto-cancel job started'
      settings = Setting.where('auto_cancel > ?', -1).
                          where('sms = ? OR send_verification_link_only = ?', true, true)
      messages = []
      settings.each do |setting|
        order_confirmations = setting.shop.order_confirmations.
                      where(status:'Pending').
                      where('created_at < ?', Time.now-setting.auto_cancel.minutes).
                      where('created_at > ?', Time.now-LOOK_BACK_DAYS.days)
        order_confirmations = only_orders_asked_to_verify(setting.shop, order_confirmations)
        setting.shop.init_session
        success_count = 0
        error_count = 0
        report_text =''
        order_confirmations.each_with_index do |order_confirmation,index|
        begin
          order = ShopifyAPI::Order.find(order_confirmation.order_id)
          if (!order.blank? && !order.financial_status.blank?) && (order.financial_status!='paid' && !order.source_name.blank? && (order.source_name!='shopify_draft_order' || (order.source_name=='shopify_draft_order' && (!order_confirmation.shop.setting.skip_draft_order)))) &&  !(setting.shop.shopify_domain=='trutuyu.myshopify.com' && order_confirmation.source_name!='web') && (order.fulfillment_status.blank? || order.fulfillment_status!='fulfilled') 
            if order_confirmation.shop.setting.auto_delete.blank? || !order_confirmation.shop.setting.auto_delete
              if order.fulfillment_status=='restocked' 
                order.cancel(email:true, reason:'declined')
              else
                order.cancel(email:true, reason:'declined', restock:true )
              end
              
              if order_confirmation.shop.shopify_domain!='beromtindia.myshopify.com'
                order.transactions.each do |transaction|
                  if (!transaction.blank? && transaction.kind=='sale')
                    begin
                    voidTransaction = ShopifyAPI::Transaction.new(:order_id=>order.id)
                    voidTransaction.order_id = order.id
                    voidTransaction.currency = transaction.currency
                    voidTransaction.amount = transaction.amount
                    voidTransaction.kind = "void"
                    voidTransaction.parent_id = transaction.id
                    
                    if !voidTransaction.save
                      SlackNotifier::CLIENT.ping(
                        text: "Unable to void transaction (#{Rails.env}) - #{order_confirmation.order_id} transaction ID #{transaction.id}",
                      )
                    end
                    rescue Exception => e
                    SlackNotifier::CLIENT.ping(
                      text: "Unable to void transaction (#{Rails.env}) - #{order_confirmation.order_id} transaction ID #{transaction.id}",
                    )
                    end
                  end
                end
              end

              order_confirmation.update(status:'COD-Auto-Cancelled')
              ShopifyJobs::TagAddJob.perform_async(order_confirmation.id, 'COD-AUTO-CANCELLED')
            else
              ShopifyAPI::Order.delete(order_confirmation.order_id)
              order_confirmation.update(status:'COD-Auto-Deleted')
              SlackNotifier::CLIENT.ping(
                text: "Order deleted (#{Rails.env}) - #{order_confirmation.id} ",
              )
            end
            if order_confirmation.shop.setting.cancel_notif_enabled
              NetworkServices::SendCancelSmsService.call(order_confirmation.id)
            end
            success_count= success_count+1
          else
            if (!order.financial_status.blank? && order.financial_status=='paid') || 
              (!order.source_name.blank? && order.source_name=='shopify_draft_order') || 
              (!order.fulfillment_status.blank? && order.fulfillment_status=='fulfilled') ||
              (setting.shop.shopify_domain=='trutuyu.myshopify.com' && order_confirmation.source_name!='web')
                order_confirmation.update(status:'COD-SKIP-CANCELLATION')
            end
            order_confirmation.update(status:'COD-SKIP-CANCELLATION')
            error_count = error_count+1
            messages.push(setting.shop.shopify_domain + ' Error in canceling order ' + order_confirmation.order_id + ' Financial status ' )
          end
        rescue Exception => e
            order_confirmation.update(status:'COD-FAILED-CANCELLATION')
            error_count = error_count+1
            messages.push(setting.shop.shopify_domain + ' Error in canceling order ' + order_confirmation.order_id )
        end
        end
        if error_count>0
         messages.push("\n#{setting.shop.shopify_domain} \n success count #{success_count} \n Error count  #{error_count}")
        end
      end
      if !messages.blank? && messages.size>0
        message_text = messages.join('\n')
        SlackNotifier::CLIENT.ping(
          text: "Auto cancel order job report (#{Rails.env}) -  #{message_text}",
        )
      end
      puts 'Auto-cancel job completed'
    end

    private

    # When WhatsApp (BSP) handles COD verification, the SMS path is skipped, so an
    # order with no cod_verification message was never asked to confirm — e.g. the
    # notification was paused or the send failed. Cancelling those would punish
    # buyers who had no chance to respond.
    def only_orders_asked_to_verify(shop, order_confirmations)
      binding = shop.whatsapp_template_bindings.find_by(event_type_key: 'cod_verification')
      return order_confirmations unless binding
      return order_confirmations unless binding.paused? || (binding.whatsapp_account || shop.default_whatsapp_account)&.ready_to_send?

      candidates = order_confirmations.to_a
      return candidates if candidates.empty?

      asked = WhatsappMessageLog.where(shop_id: shop.id, event_type_key: 'cod_verification',
                                       source_external_id: candidates.map { |oc| oc.order_id.to_s })
                                .where.not(status: %i[failed dropped])
                                .distinct.pluck(:source_external_id).to_set
      candidates.select { |oc| asked.include?(oc.order_id.to_s) }
    end
  end

end
