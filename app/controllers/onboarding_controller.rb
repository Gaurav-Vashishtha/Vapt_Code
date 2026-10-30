# frozen_string_literal: true

class OnboardingController < ApplicationController
    include ShopifyApp::EmbeddedApp
    include ShopifyApp::RequireKnownShop
    include ShopContextInitializer
    before_action :set_shop
  
    def index
      result = prepare_shop_context(shop: @shop, session: session, request: request, response: response)

      @upgrade_status = ''
      if @shop && params['charge_id']
        @shop.init_session
        recurring_charge = ShopifyAPI::RecurringApplicationCharge.find(
          request.params['charge_id']
        )
        if recurring_charge.status == 'active' and
           request.params['charge_id'] != @shop.charge_id
          @shop.update(
            plan: Plan.find(params['plan_id']), charge_id: request.params['charge_id']
          )
          WelcomeMailer.plan_upgrade(
            @shop.owner_email, {
              name: @shop.shop_owner,
              shopify_domain: @shop.shopify_domain,
              owner_name: @shop.owner_name
            }).deliver_later
          ChargeActivatedJob.perform_now @shop.id
          @upgrade_status = 'success'
          if @shop.plan.name != 'Free' && (@shop.setting.lock_paid_feature==true)
            @shop.setting.update(lock_paid_feature:false)
            resp = ShopifyServices::PaymentCustomizationService.call(@shop , '')
            if resp.blank?
              SlackNotifier::CLIENT.ping(
                text: "Error refreshing meta fields while unlocking the shop - #{@shop.shopify_domain}",
              )
            end
          end
        else
          @upgrade_status = 'error'
        end
      end


        @shop_origin = result[:shop_origin]
        @setting = result[:setting]
        @plan = result[:plan]
        @crisp_url = result[:crisp_url]
        @twilio_pricing = result[:twilio_pricing]
        @visible_plans = result[:visible_plans]

        render "onboarding/index"
    end
  
    private
  
    def set_shop
      @shop = Shop.find_by(shopify_domain: current_shopify_domain)
    end
  end
  