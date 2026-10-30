# frozen_string_literal: true

# Philippines SMS: shops with id <= SHOP_ID_THRESHOLD keep TwilioPricing DB rates;
# shops after that (and unauthenticated pricing) use a fixed USD base before plan multipliers.
module PhilippinesSmsRate
  SHOP_ID_THRESHOLD = 85700
  NEW_MERCHANT_SMS_BASE_USD = 0.04

  module_function

  def effective_sms_base_usd(country_code:, shop_id:, db_sms_price:)
    return db_sms_price unless country_code.to_s.upcase == "PH"

    if shop_id.present? && shop_id.to_i <= SHOP_ID_THRESHOLD
      db_sms_price
    else
      NEW_MERCHANT_SMS_BASE_USD
    end
  end
end
