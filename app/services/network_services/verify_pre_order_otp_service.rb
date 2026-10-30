module NetworkServices
  class VerifyPreOrderOtpService < ApplicationService
    # params = {"country_code"=>"IN", "phone"=>"919130751989", "otp"=>"3369", "ip_address"=>"10.1.1.14", "device_id"=>"abjdsjdhs"}
    # NetworkServices::VerifyPreOrderOtpService.call(Shop.last.id, params)

    def verify
      pastOtps = PreOrderOtp.otp_sends.where(device_id: @params['device_id'])
        .where(phone: @params['phone'])
        .where("created_at >= ?", 30.minutes.ago)
        .order(Arel.sql("pre_order_otps.created_at DESC"))
    
      if pastOtps.present?
        if pastOtps.first.otp == @params['otp']
          pastOtps.first.update(verification_status: 'OTP-Verified')
          return true
        end
      end
    
      if !@params['phone'].strip.starts_with?('+')
        pastOtps = PreOrderOtp.otp_sends.where(device_id: @params['device_id'])
          .where(phone: "+" + @params['phone'])
          .where("created_at >= ?", 30.minutes.ago)
          .order(Arel.sql("pre_order_otps.created_at DESC"))
    
        if pastOtps.present?
          if pastOtps.first.otp == @params['otp']
            pastOtps.first.update(verification_status: 'OTP-Verified')
            return true
          end
        end
      end
    
      return false
    end
    

    def initialize(shop_id, params)
      @shop = Shop.find(shop_id)
      @params = params
    end

    def clean_phone_number(phone, country_code)
      if !phone.blank?
        phone = phone.tr('^0-9', '').sub!(/^0*/, '')
      end
      Phonelib.parse(phone, country_code).to_s
    rescue Exception => e
      SlackNotifyJob.perform_async(
        ":rage:  (#{Rails.env})\n *Error* Phonelib parse \n Phone: #{phone}  \n country_code: #{country_code} \n error: #{e.message}"
      )
      phone
    end

    def call
      result = {}
      if PreOrderOtpCheckoutPageGuard.checkout_page_request?(@params) &&
          !PreOrderOtpCheckoutPageGuard.allowed_for_checkout_api?(@shop)
        return {
          verification: false,
          status: "error",
          Notes: "Checkout extension OTP is not enabled for this billing plan.",
          code: "checkout_otp_plan_forbidden"
        }
      end

      @params['phone'] = clean_phone_number(@params['phone'], @params['country_code'])
      is_verified = verify
      result['verification'] = is_verified
      result['status'] = 'success'
      phone = @params['phone']
      phone = "+#{phone}" unless phone.strip.starts_with?('+')
      
      if is_verified && fetch_shipping_address_for_verify?
        shipping_data = Customer.fetch_shipping_address_by_phone(phone)
        result.merge!(shippingAddress: shipping_data)
      end

      if is_verified && @shop.setting.pre_is_login_enabled
        customer_logins = CustomerLogin.where(phone:phone).where(shopify_domain:@shop.shopify_domain)
        if customer_logins.count>0
          result['customerLogin'] = customer_logins.first
        else
          result['customerLogin'] = {}
        end
      end

      if is_verified
        begin
          result['sso_session_token'] = SsoJwtService.issue(phone: phone, country_code: @params['country_code'])
        rescue => e
          Rails.logger.error "[SSO] Failed to issue JWT: #{e.message}"
        end
        email = Customer.real_email(@params['email'].presence || @params[:email].presence)
        CodFormCustomerSyncJob.perform_async(@shop.id, phone, email, nil)
      end

      result
    end

    private

    # Match frontend: gateway configured in private_payment_provider (e.g. Razorpay partial pay)
    # or legacy prepaid columns — then also return shipping addresses on verify.
    def fetch_shipping_address_for_verify?
      s = @shop.setting
      return true if s.is_prefilled_address_enabled || s.cod_form_enabled

      payment_provider_configured?(s)
    end

    def payment_provider_configured?(setting)
      pp = setting.private_payment_provider
      if pp.is_a?(String)
        begin
          pp = JSON.parse(pp)
        rescue JSON::ParserError
          pp = nil
        end
      end

      if pp.is_a?(Hash)
        return true if %w[name].any? { |k| pp[k].present? }
      end

      setting.payment_provider.present? &&
        setting.payment_provider_api_key.present? &&
        setting.payment_provider_api_secret.present?
    end
  end
end
