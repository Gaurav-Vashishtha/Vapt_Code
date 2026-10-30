module NetworkServices
  class FreeWalletService < ApplicationService
    attr_reader :shop

    EXCLUDED_DOMAINS = %w[
      easysell1.myshopify.com
      easysell2.myshopify.com
      easysell3.myshopify.com
      easysell4.myshopify.com
      easysell5.myshopify.com
      test-sso-store-11.myshopify.com
      test-store-discounts-2.myshopify.com
    ].freeze

    DEFAULT_PARTIAL_FEE_RATE = 0.015 # 1.5%

    def initialize(shop, country_code = '', mode = 'SMS')
      @country_code = country_code
      @mode = mode
      @shop = shop
    end

    def call
      if @shop.charge_id.blank? && !EXCLUDED_DOMAINS.include?(@shop.shopify_domain)
        wallet = Wallet.find_by(shopify_domain: @shop.shopify_domain)
        if wallet.blank?
          wallet = Wallet.find_or_initialize_by(shopify_domain: @shop.shopify_domain)
          wallet.save
        end
        pricings = TwilioPricing.all.index_by(&:country_code)
        price = 0
        if @mode == 'SMS'
          db_sms = pricings[@country_code]["sms_price"].to_f
          price = PhilippinesSmsRate.effective_sms_base_usd(
            country_code: @country_code,
            shop_id: @shop.id,
            db_sms_price: db_sms
          )
        else
          price = pricings[@country_code]["whatsapp"].to_f
        end
        wallet.update(balance_used: wallet.balance_used + price)
        lock_shop_if_exhausted(wallet)
      end
    end

    # Deduct partial payment transaction fees from free wallet for all uncharged partial payment
    # orders (for shops with no charge_id). Uses same scope and fee logic as DynamicChargeJob:
    # status 'COD-Partial-Payment-Received', is_prepaid_charged nil; order amount in USD × rate (default 1.5%).
    def self.deduct_partial_payment(shop, _order_confirmation = nil)
      return if shop.charge_id.present?
      return if FreeWalletService::EXCLUDED_DOMAINS.include?(shop.shopify_domain)

      partial_payment_orders = shop.order_confirmations.where(status: 'COD-Partial-Payment-Received', is_prepaid_charged: nil)
      return if partial_payment_orders.empty?

      wallet = Wallet.find_by(shopify_domain: shop.shopify_domain)
      wallet ||= Wallet.find_or_initialize_by(shopify_domain: shop.shopify_domain)
      wallet.save if wallet.new_record?

      rate = shop.setting&.partial_transaction_fee.to_f
      rate = DEFAULT_PARTIAL_FEE_RATE if rate <= 0

      total_fee = 0.0

      partial_payment_orders.each do |order|
        begin
          full_order = if order.draft_order_id.present?
                         shop.order_confirmations.find_by(order_id: order.draft_order_id) || order
                       else
                         order
                       end
          total_amount = (full_order&.order_amount || 0).to_f
          next if total_amount <= 0

          original_currency = (order.currency || 'INR').to_s
          usd_value = usd_value_from(total_amount, original_currency)
          fee = (usd_value * rate).round(4)
          next if fee <= 0

          total_fee += fee
        rescue StandardError => e
          Rails.logger.error "FreeWalletService partial payment fee failed for order #{order.id}: #{e.message}"
        end
      end

      return if total_fee <= 0

      wallet.update!(balance_used: wallet.balance_used + total_fee)

      lock_shop_if_exhausted(shop, wallet)
    end

    def self.lock_shop_if_exhausted(shop, wallet)
      return unless (wallet.total_balance.to_f - wallet.balance_used.to_f) <= 0

      shop.setting.update(
        locked: true,
        sms: false,
        ivr: false,
        status: false,
        cod_fee_enabled: false,
        abandoned_cart_enabled: false,
        enable_fulfilment_message: false,
        confirmation_sms_enabled: false,
        partial_payment_enabled: false,
        lock_paid_feature: true
      )
      WelcomeMailer.lock_shop(shop.id).deliver_later
    end

    def self.usd_value_from(amount, currency)
      money = Money.new((amount * 100).to_i, currency)
      money.exchange_to('USD').to_f
    rescue Money::Bank::UnknownRate, NoMethodError
      fallback_rate = ExchangeRateBank.fallback_usd_rate(currency) || ExchangeRateBank.fallback_usd_rate('INR')
      amount * fallback_rate
    end

    private

    def lock_shop_if_exhausted(wallet)
      return unless (wallet.total_balance.to_f - wallet.balance_used.to_f) <= 0

      @shop.setting.update(
        locked: true,
        sms: false,
        ivr: false,
        status: false,
        cod_fee_enabled: false,
        abandoned_cart_enabled: false,
        enable_fulfilment_message: false,
        confirmation_sms_enabled: false,
        partial_payment_enabled: false,
        lock_paid_feature: true
      )
      WelcomeMailer.lock_shop(@shop.id).deliver_later
    end
  end
end