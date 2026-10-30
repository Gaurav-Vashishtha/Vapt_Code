class OldOrderVerificationJob < ApplicationJob
  include TwilioHelper
  sidekiq_options queue: 'low'
  # OldOrderVerificationJob.perform_async( 13, '3864605753515','Hi {{link}} is verification link')
  MAX_TRIES = 5

  def perform(shop_id, _order_id, _template)
    shop = Shop.find(shop_id)
    shop.init_session
    order = ShopifyAPI::Order.find(_order_id)
    resp = OrderConfirmationServices::OrderConfirmationPostService.call(shop, order)
    if resp && !resp['id'].blank?
      if shop.setting.sms
        call_sms_twillio(resp, _template)
      else
        call_ivr_twillio(resp, shop) # Not tested flow...
      end
    end
  end

  def call_sms_twillio(order_confirmation, template)
    Sidekiq::Client.push(
      'class' => NetworkJobs::SendSmsJob,
      'queue' => 'low',
      'args' => [
        order_confirmation.shop.id, order_confirmation.id, template,
        order_confirmation.shop.setting.dlt_bulk_template_id
      ],
    )
  end

  # Not tested flow...
  def call_ivr_twillio(order_confirmation, shop)
    if !order_confirmation.customer_number.blank? && order_confirmation.notif_count < MAX_TRIES
      request = build_twiml(
        shop.primary_locale&.to_sym,
        shop.setting.ivr_introduction,
        shop.setting.ivr_confirm_message,
        shop.setting.ivr_cancel_message,
        '/twillio/ivr_webhook'
      )
      resp = TwilioServices::IvrCallService.call({
                                                   from: ENV['TWILIO_PHONE_NUMBER'],
                                                   to: order_confirmation.customer_number,
                                                   twiml: request,
                                                 })
      order_confirmation.update(ivr_sid: resp.sid)
      order_confirmation.increment!(:notif_count)
      TwilioLog.create(
        sid: resp.sid,
        ver_type: 'IVR',
        country_code: order_confirmation.country_code,
        customer_number: order_confirmation.customer_number,
        status: resp.sid ? 'SUCCESS' : resp.error,
        order_confirmation: order_confirmation,
        shop: shop,
      )
    else
      SlackNotifyJob.perform_async(
        ':rage:  (#{Rails.env})\n  *Error* Order reached max tries order_id #{order_confirmation.order_id}'
      )
    end
  end
end
