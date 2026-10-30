# frozen_string_literal: true

# Async Admin API work for Built for Shopify Forms criteria (segments, customerSegmentMembers, customer create/update).
class CodFormCustomerSyncJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 2

  def perform(shop_id, phone, email = nil, customer_name = nil)
    shop = Shop.find_by(id: shop_id)
    if shop.blank? || phone.blank?
      Rails.logger.info "[CodFormCustomerSyncJob] skip shop_id=#{shop_id} shop_blank=#{shop.blank?} phone_blank=#{phone.blank?}"
      return { success: false, error: "missing_shop_or_phone" }
    end

    first_name, last_name = split_customer_name(customer_name)
    result = ShopifyServices::FormsCustomerSyncService.call(
      shop,
      phone: phone,
      email: email.presence,
      first_name: first_name,
      last_name: last_name
    )

    Rails.logger.info "[CodFormCustomerSyncJob] #{result.to_json}"

    result
  end

  private

  def split_customer_name(raw)
    s = raw.to_s.strip
    return [nil, nil] if s.blank?

    parts = s.split(/\s+/, 2)
    [parts[0].presence, parts[1].presence]
  end
end
