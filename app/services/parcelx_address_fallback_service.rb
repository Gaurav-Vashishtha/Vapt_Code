class ParcelxAddressFallbackService < ApplicationService
  SOURCE_PREFIX = 'parcelx:'.freeze
  MISS_CACHE_KEY_PREFIX = 'parcelx:address:miss:'.freeze
  # shipping_cache LRU holds only 100 phones and misses are never stored there,
  # so without this negative cache every repeat lookup of an unknown phone
  # would hit the paid ParcelX API again.
  MISS_CACHE_TTL = 24.hours.to_i

  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('PARCELX_FALLBACK_ENABLED', 'true'))
  end

  attr_reader :phone

  def initialize(phone)
    @phone = phone.to_s
  end

  def call
    return nil unless self.class.enabled?
    return nil unless indian_phone?
    return nil if recently_missed?

    records = NetworkServices::ParcelxAddressService.call(phone)

    if records.blank?
      CodKingStat.increment_stat('parcelx_address_miss')
      mark_missed
      return nil
    end

    CodKingStat.increment_stat('parcelx_address_hit')
    persist(records)
  end

  private

  def digits
    @digits ||= phone.gsub(/\D/, '')
  end

  def indian_phone?
    last10 = digits.last(10)
    return false unless last10.length == 10 && ('6'..'9').cover?(last10[0])

    digits.length == 10 || (digits.length == 12 && digits.start_with?('91'))
  end

  def miss_key
    "#{MISS_CACHE_KEY_PREFIX}#{phone}"
  end

  def recently_missed?
    Sidekiq.redis { |redis| redis.get(miss_key).present? }
  rescue => e
    Rails.logger.warn("[parcelx_fallback] miss-cache read failed: #{e.class}: #{e.message}")
    false
  end

  def mark_missed
    Sidekiq.redis { |redis| redis.setex(miss_key, MISS_CACHE_TTL, 1) }
  rescue => e
    Rails.logger.warn("[parcelx_fallback] miss-cache write failed: #{e.class}: #{e.message}")
  end

  def persist(records)
    customer = Customer.find_or_create_by(phone: phone)
    fill_customer_profile(customer, records)

    records.each do |record|
      attrs = map_address(record)
      next if attrs.blank?

      address = customer.customer_addresses.find_or_initialize_by(shopify_id: attrs[:shopify_id])
      next unless address.new_record?

      address.assign_attributes(attrs)
      address.save
    end

    customer
  rescue => e
    Rails.logger.error("[parcelx_fallback] persist failed phone=#{phone}: #{e.class}: #{e.message}")
    nil
  end

  def fill_customer_profile(customer, records)
    updates = {}
    if customer.email.blank?
      email = records.map { |r| Customer.real_email(r['email']) }.find(&:present?)
      updates[:email] = email if email
    end
    if customer.first_name.blank? && customer.last_name.blank?
      name = records.map { |r| r['name'] }.find(&:present?)
      if name
        first_name, last_name = split_name(name)
        updates[:first_name] = first_name
        updates[:last_name] = last_name
      end
    end
    customer.update(updates) if updates.present?
  end

  def map_address(record)
    address1 = record['address1'].presence || record['line1'].presence || record['address'].presence
    return nil if address1.blank?

    record_id = record['_id'].presence || Digest::MD5.hexdigest(address1)
    first_name, last_name = split_name(record['name'])

    {
      shopify_id: "#{SOURCE_PREFIX}#{record_id}",
      first_name: first_name,
      last_name: last_name,
      address1: address1,
      address2: record['address2'].presence || record['line2'].presence,
      city: record['city'].presence,
      province: record['state'].presence,
      zip: record['pincode'].presence,
      phone: phone,
      country: 'India',
      country_code: 'IN',
      country_code_v2: 'IN'
    }
  end

  def split_name(name)
    parts = name.to_s.strip.split(/\s+/, 2)
    [parts[0], parts[1]]
  end
end
