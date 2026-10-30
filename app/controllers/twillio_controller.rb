require 'twilio-ruby'

class TwillioController < ApplicationController

  # POST ivr/webhook
  def ivr_webhook
    @order_confirmation = OrderConfirmation.find_by(ivr_sid: params[:CallSid])
    response = Twilio::TwiML::VoiceResponse.new
    response.gather(num_digits: '1') do |gather|
    if params[:Digits]==="1"
       gather.say(message: I18n.t('admin.confirmed_thank_you'))
       verification_tag =
         @order_confirmation.shop.setting&.verification_tag.presence ||
         ShopifyJobs::OrderPostJob::DEFAULT_VERIFICATION_TAG
       ShopifyServices::OrderPostService.call(
        @order_confirmation.shop,
        @order_confirmation.order_id,
        verification_tag,
        params[:Called]
      )
      @order_confirmation.update(status: 'COD-Verified', confirmed_at: Time.new, is_otp_verified: true)
      CodFormCustomerSyncJob.perform_async(
        @order_confirmation.shop_id,
        @order_confirmation.customer_number,
        @order_confirmation.customer_email,
        @order_confirmation.customer_name
      )
    elsif params[:Digits]==="2"
       gather.say(message: I18n.t('admin.cancelled_thank_you'))
       ShopifyServices::OrderPostService.call(
        @order_confirmation.shop,
        @order_confirmation.order_id,
        ShopifyJobs::OrderPostJob::CUSTOMER_CANCELLED_TAG,
        params[:Called]
      )
      @order_confirmation.update(status: 'COD-Cancelled', confirmed_at: Time.new)
    elsif !(params[:Digits]==="1" || params[:Digits]==="2")
        gather.say(message: I18n.t('admin.invalid_thank_you'))
    end
  end
  render xml: response.to_s
  end

  # POST test_ivr_webhook
  def test_ivr_webhook
    response = Twilio::TwiML::VoiceResponse.new
    response.gather(num_digits: '1') do |gather|
    if params[:Digits]==="1"
       gather.say(message: I18n.t('admin.confirmed_thank_you'))
    elsif params[:Digits]==="2"
       gather.say(message: I18n.t('admin.cancelled_thank_you'))
    elsif !(params[:Digits]==="1" || params[:Digits]==="2")
        gather.say(message: I18n.t('admin.invalid_thank_you'))
    end
  end
  render xml: response.to_s
  end
end