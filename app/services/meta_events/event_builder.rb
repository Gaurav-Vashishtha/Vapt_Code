# frozen_string_literal: true

module MetaEvents
  # Turns one wire event from the web pixel into one Conversions API event hash.
  # https://developers.facebook.com/docs/marketing-api/conversions-api/parameters
  class EventBuilder
    EVENT_NAMES = %w[
      PageView ViewContent ViewCategory Search AddToCart RemoveFromCart ViewCart
      InitiateCheckout AddPaymentInfo Purchase Subscribe Lead
    ].freeze

    # Shared with the COD form leg so both report the same columns for one order.
    CAMPAIGN_KEYS = ::CampaignAttributionHelper::ALLOWED_KEYS
    CAMPAIGN_VALUE_MAX = 500

    CUSTOM_DATA_KEYS = (%w[
      value currency num_items content_type content_ids contents content_name
      content_category search_string order_id amount_collected subscription_id
    ] + CAMPAIGN_KEYS).freeze

    HASHED_KEYS = %w[em ph fn ln ct st zp country external_id].freeze
    PLAIN_KEYS = %w[fbp fbc].freeze

    # Meta asks every CAPI integration to identify itself; the native Shopify app does too.
    PARTNER_AGENT = "codking-shopify-1.0"

    SHA256_HEX = /\A[a-f0-9]{64}\z/

    def initialize(event, client_ip:, client_user_agent:)
      @event = event.is_a?(Hash) ? event : {}
      @client_ip = client_ip
      @client_user_agent = client_user_agent
    end

    def self.build_all(events, client_ip:, client_user_agent:)
      Array(events).filter_map do |event|
        new(event, client_ip: client_ip, client_user_agent: client_user_agent).build
      end
    end

    def build
      name = @event["event_name"].to_s
      return nil unless EVENT_NAMES.include?(name)

      user_data = build_user_data
      return nil unless matchable?(user_data)

      payload = {
        event_name: name,
        event_id: @event["event_id"].to_s.presence,
        event_time: event_time,
        action_source: "website",
        partner_agent: PARTNER_AGENT,
        event_source_url: string_value(@event["event_source_url"]),
        user_data: user_data,
        custom_data: build_custom_data.presence,
      }.compact

      # CCPA Limited Data Use, forwarded from the pixel's saleOfDataAllowed consent.
      if Array(@event["data_processing_options"]).include?("LDU")
        payload[:data_processing_options] = ["LDU"]
        payload[:data_processing_options_country] = 0
        payload[:data_processing_options_state] = 0
      end

      payload
    end

    private

    # Meta drops a website event that carries no way to identify the visitor.
    def matchable?(user_data)
      return true if (user_data.keys & %i[em ph external_id fbp fbc]).any?

      user_data[:client_ip_address].present? && user_data[:client_user_agent].present?
    end

    # Meta rejects events dated more than 7 days back or in the future, and a clock-skewed
    # browser is the common cause, so the client value is only trusted inside that window.
    def event_time
      now = Time.now.to_i
      claimed = @event["event_time"].to_i
      return now if claimed <= 0
      return now if claimed > now + 60
      return now if claimed < now - 7.days.to_i

      claimed
    end

    def build_user_data
      raw = user_data_hash
      data = {}

      HASHED_KEYS.each do |key|
        hashed = hash_for(key, raw[key])
        data[key.to_sym] = [hashed] if hashed.present?
      end

      PLAIN_KEYS.each do |key|
        value = string_value(raw[key])
        data[key.to_sym] = value if value.present?
      end

      data[:client_ip_address] = @client_ip if @client_ip.present?
      data[:client_user_agent] = ua_for_event if ua_for_event.present?
      data
    end

    def ua_for_event
      @ua_for_event ||= string_value(@event["client_user_agent"]).presence || @client_user_agent
    end

    # The pixel sends raw values; anything already SHA-256 hex is passed through so a
    # future client-side hashing change doesn't double-hash.
    def hash_for(key, value)
      raw = string_value(value)
      return nil if raw.blank?
      return raw.downcase if raw.match?(SHA256_HEX)

      normalized = normalize(key, raw)
      return nil if normalized.blank?

      Digest::SHA256.hexdigest(normalized)
    end

    # Kept byte-identical to META_NORMALIZE in the web pixel so the hash on the browser
    # hit and the hash on the server event resolve to the same person.
    def normalize(key, raw)
      case key
      when "ph" then normalize_phone(raw)
      when "fn", "ln", "st" then raw.downcase.gsub(/[^[[:alpha:]]]/, "")
      when "ct" then raw.downcase.gsub(/[^[[:alnum:]]]/, "")
      when "zp" then raw.downcase.gsub(/[\s-]/, "")
      when "country" then raw.downcase.gsub(/[^[[:alpha:]]]/, "")[0, 2]
      when "external_id" then raw
      else raw.downcase
      end
    end

    # Meta matches on a phone that carries its country code. The pixel can't add one
    # (no libphonenumber in the sandbox), so it forwards the address country as a hint
    # and the dialing code is resolved here.
    def normalize_phone(raw)
      hint = string_value(user_data_hash["ph_country"]).to_s.upcase.presence
      parsed = Phonelib.parse(raw, hint)
      digits = parsed.valid? ? parsed.e164.to_s.delete("+") : raw.gsub(/\D/, "").sub(/\A0+/, "")

      return nil if digits.length < 8 || digits.length > 15

      digits
    end

    def user_data_hash
      raw = @event["user_data"]
      raw.is_a?(Hash) ? raw : {}
    end

    def build_custom_data
      raw = @event["custom_data"]
      return {} unless raw.is_a?(Hash)

      data = {}
      CUSTOM_DATA_KEYS.each do |key|
        value = raw[key]
        next if value.nil?
        next if value.respond_to?(:empty?) && value.empty?

        data[key.to_sym] =
          case key
          when "value", "amount_collected" then value.to_f
          when "num_items" then value.to_i
          when "contents" then normalize_contents(value)
          when "content_ids" then Array(value).map(&:to_s)
          when *CAMPAIGN_KEYS then string_value(value).to_s.byteslice(0, CAMPAIGN_VALUE_MAX).presence
          else value.to_s
          end
      end

      data[:contents] = nil if data[:contents].blank?
      data.compact
    end

    def normalize_contents(value)
      return nil unless value.is_a?(Array)

      value.filter_map do |item|
        next unless item.is_a?(Hash)

        id = item["id"].to_s
        next if id.blank?

        entry = { id: id, quantity: item["quantity"].to_i }
        entry[:item_price] = item["item_price"].to_f if item["item_price"].present?
        entry
      end.presence
    end

    def string_value(value)
      return nil if value.nil?

      # Non-ASCII sneaks in from copy-pasted merchant data and breaks the JSON body encoding.
      value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "").strip
    end
  end
end
