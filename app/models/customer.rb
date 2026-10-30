class Customer < ApplicationRecord
  has_many :customer_addresses, dependent: :destroy
  has_many :customer_shop_mappings, dependent: :destroy

  # v2: address-quality filters changed; old cache entries hold unfiltered lists
  SHIPPING_CACHE_DATA_KEY = 'shipping_cache:data:v2'.freeze
  SHIPPING_CACHE_LRU_KEY  = 'shipping_cache:lru:v2'.freeze
  SHIPPING_CACHE_MAX_SIZE = 100
  PLACEHOLDER_EMAIL_REGEX = /\Ano-?email[-_]?\d*@/i

  def self.placeholder_email?(email)
    email.to_s.strip.match?(PLACEHOLDER_EMAIL_REGEX)
  end

  def self.real_email(email)
    value = email.to_s.strip
    return nil if value.blank? || placeholder_email?(value)

    value
  end

  def self.invalidate_shipping_address_cache_by_phone(raw_phone)
    phone = normalize_shipping_phone(raw_phone)

    Sidekiq.redis do |redis|
      redis.hdel(SHIPPING_CACHE_DATA_KEY, phone)
      redis.zrem(SHIPPING_CACHE_LRU_KEY, phone)
    end
  end

  def self.fetch_shipping_address_by_phone(raw_phone, track_stat: true)
    phone = normalize_shipping_phone(raw_phone)

    cached = read_shipping_cache(phone)
    if cached
      record_shipping_stat(cached, track_stat)
      return cached
    end

    shipping_data = usable_addresses_for(phone)

    if shipping_data.blank? && ParcelxAddressFallbackService.call(phone)
      shipping_data = usable_addresses_for(phone)
    end

    if shipping_data.blank?
      record_shipping_stat(nil, track_stat)
      return nil
    end

    write_shipping_cache(phone, shipping_data)
    record_shipping_stat(shipping_data, track_stat)
    shipping_data
  end

  # Overall prefill outcome (DB + ParcelX combined). Key spelling is
  # historical — keep it so the stat series stays continuous.
  def self.record_shipping_stat(shipping_data, track_stat)
    return unless track_stat

    key = shipping_data.present? ? 'shiiping_address_hit' : 'shiiping_address_miss'
    CodKingStat.increment_stat(key)
  rescue => e
    Rails.logger.warn("[shipping_stats] #{e.class}: #{e.message}")
  end

  def self.normalize_shipping_phone(raw_phone)
    phone = raw_phone.gsub(' ', '')
    phone = "+#{phone}" unless phone.strip.start_with?('+')
    phone
  end

  def self.read_shipping_cache(phone)
    Sidekiq.redis do |redis|
      cached = redis.hget(SHIPPING_CACHE_DATA_KEY, phone)
      return nil unless cached

      redis.zadd(SHIPPING_CACHE_LRU_KEY, Time.now.to_f, phone)
      JSON.parse(cached)
    end
  end

  def self.write_shipping_cache(phone, shipping_data)
    Sidekiq.redis do |redis|
      redis.hset(SHIPPING_CACHE_DATA_KEY, phone, shipping_data.to_json)
      redis.zadd(SHIPPING_CACHE_LRU_KEY, Time.now.to_f, phone)

      if redis.zcard(SHIPPING_CACHE_LRU_KEY) > SHIPPING_CACHE_MAX_SIZE
        lru_phone = redis.zrange(SHIPPING_CACHE_LRU_KEY, 0, 0).first
        redis.hdel(SHIPPING_CACHE_DATA_KEY, lru_phone)
        redis.zrem(SHIPPING_CACHE_LRU_KEY, lru_phone)
      end
    end
  end

  def self.usable_addresses_for(phone)
    customer = Customer.find_by(phone: phone)
    return nil unless customer

    rank_addresses(customer.customer_addresses.as_json)
  end

  def self.rank_addresses(addresses)
    addresses = addresses.reject do |addr|
      gibberish_address?(addr['address1']) ||
        addr['address1'].to_s.strip.length < 10 ||
        incomplete_address?(addr)
    end

    addresses = deduplicate_addresses(addresses)

    # Coordinates-validated addresses first, then most-recently-updated within each group.
    addresses.sort_by! do |addr|
      validated_rank = coordinates_validated?(addr['coordinates_validated']) ? 0 : 1
      updated_at_ts = (Time.parse(addr['updated_at'].to_s) rescue Time.at(0)).to_f
      [validated_rank, -updated_at_ts]
    end

    addresses.first(10).each { |addr| addr['source'] = address_source(addr) }
  end

  def self.address_source(addr)
    addr['shopify_id'].to_s.start_with?(ParcelxAddressFallbackService::SOURCE_PREFIX) ? 'parcelx' : 'shopify'
  end

  def self.deduplicate_addresses(addresses)
    return [] if addresses.empty?

    unique_addresses = []
    # Similarity threshold: addresses with similarity >= 0.85 (85%) are considered duplicates
    similarity_threshold = 0.85

    addresses.each do |addr|
      is_duplicate = false

      unique_addresses.each do |unique_addr|
        if addresses_similar?(addr, unique_addr, similarity_threshold)
          is_duplicate = true
          break
        end
      end

      unique_addresses << addr unless is_duplicate
    end

    unique_addresses
  end

  def self.addresses_similar?(addr1, addr2, threshold)
    location_match = (
      normalize_field(addr1['city']) == normalize_field(addr2['city']) &&
      normalize_field(addr1['province']) == normalize_field(addr2['province']) &&
      normalize_field(addr1['zip']) == normalize_field(addr2['zip']) &&
      normalize_field(addr1['country_code']) == normalize_field(addr2['country_code'])
    )

    return false unless location_match

    addr1_normalized = normalize_address_line(addr1['address1'])
    addr2_normalized = normalize_address_line(addr2['address1'])

    similarity = string_similarity(addr1_normalized, addr2_normalized)

    similarity >= threshold
  end

  def self.normalize_address_line(address)
    return '' if address.blank?

    normalized = address.to_s.downcase.strip

    normalized = normalized.gsub(/\s+/, ' ')

    abbreviations = {
      /\bstreet\b/ => 'st',
      /\broad\b/ => 'rd',
      /\bavenue\b/ => 'ave',
      /\bdrive\b/ => 'dr',
      /\blane\b/ => 'ln',
      /\bboulevard\b/ => 'blvd',
      /\bapartment\b/ => 'apt',
      /\bapt\b/ => 'apt',
      /\bunit\b/ => 'unit',
      /\bnumber\b/ => 'no',
      /\bno\b/ => 'no',
      /\b#\b/ => 'no'
    }

    abbreviations.each do |pattern, replacement|
      normalized = normalized.gsub(pattern, replacement)
    end

    normalized = normalized.gsub(/[.,;:]/, '')

    normalized.strip
  end

  def self.normalize_field(field)
    field.to_s.downcase.strip.gsub(/\s+/, ' ')
  end

  def self.string_similarity(str1, str2)
    return 1.0 if str1 == str2
    return 0.0 if str1.blank? || str2.blank?

    distance = levenshtein_distance(str1, str2)

    max_length = [str1.length, str2.length].max
    return 1.0 if max_length == 0

    1.0 - (distance.to_f / max_length)
  end

  def self.levenshtein_distance(str1, str2)
    m = str1.length
    n = str2.length

    return n if m == 0
    return m if n == 0

    d = Array.new(m + 1) { Array.new(n + 1) }

    (0..m).each { |i| d[i][0] = i }
    (0..n).each { |j| d[0][j] = j }

    (1..m).each do |i|
      (1..n).each do |j|
        cost = str1[i - 1] == str2[j - 1] ? 0 : 1
        d[i][j] = [
          d[i - 1][j] + 1,
          d[i][j - 1] + 1,
          d[i - 1][j - 1] + cost
        ].min
      end
    end

    d[m][n]
  end

  # coordinates_validated is stored as a string ("true"/"false"/nil) — accept any truthy variant.
  def self.coordinates_validated?(value)
    ActiveModel::Type::Boolean.new.cast(value) == true
  end

  # A usable street address has at least two real words across address1+address2;
  # single-word entries ("Bangalore", "Rajahmundry533101") are city-only junk.
  def self.incomplete_address?(addr)
    full = "#{addr['address1']} #{addr['address2']}"
    words = full.split(/[\s,]+/).select { |w| w.gsub(/[^a-zA-Z0-9]/, '').length >= 2 }
    words.length < 2
  end

  def self.gibberish_address?(address)
    return true if address.blank?
    cleaned = address.gsub(/[^a-zA-Z]/, '')
    return true if cleaned.length < 5
    return true if cleaned =~ /^(.)\1{4,}$/
    return true if cleaned.scan(/[a-zA-Z]/).empty?
    false
  end
end
