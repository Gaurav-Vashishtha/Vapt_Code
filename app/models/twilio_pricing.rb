class TwilioPricing < ActiveRecord::Base
  # JSON for embedded app / billing: PH SMS base respects legacy vs new-merchant rule.
  def self.payload_for_shop(shop)
    record = find_by(country_code: shop.country_code) ||
             find_by(country_code: "US") ||
             find_by(country_code: "IN") ||
             first
    return {} unless record

    h = record.as_json.stringify_keys
    h["sms_price"] = PhilippinesSmsRate.effective_sms_base_usd(
      country_code: record.country_code,
      shop_id: shop.id,
      db_sms_price: record.sms_price.to_f
    )
    h
  end
end