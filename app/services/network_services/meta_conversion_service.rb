# frozen_string_literal: true

module NetworkServices
  class MetaConversionService
    API_VERSION = "v19.0"
    SLACK_PAYLOAD_TRUNCATE_CHARS = 3200
    META_CLICK_KEYS = %i[fbp fbc fbclid event_source_url client_user_agent phone].freeze

    # JSON API sends nested hashes as ActionController::Parameters — not Hash — so is_a?(Hash) was false and fbp/fbc were dropped.
    def self.coerce_meta_click_hash(raw)
      return {} if raw.blank?
      if raw.respond_to?(:permit)
        raw.permit(*META_CLICK_KEYS).to_h
      elsif raw.is_a?(Hash)
        raw
      else
        {}
      end
    end

    # When false, skip Meta CAPI calls and omit attribution fields from payloads (OTP-only merchants).
    def self.meta_conversion_enabled?(setting)
      return true if setting.nil?
      return true unless setting.has_attribute?(:conversion_tracking)

      setting.conversion_tracking != false
    end

    def initialize(order, updated_amount, setting = nil, meta_click_data: nil, client_context: nil, campaign_attribution: nil)
      @order = order
      @updated_amount = updated_amount # The amount of the partial/edited payment
      @setting = setting
      # Strip non-ASCII (e.g. U+2060 WORD JOINER from copy-paste) so URI is valid
      @pixel_id = ascii_only(@setting&.pixel_id.to_s).presence
      @access_token = ascii_only(@setting&.pixel_token.to_s).presence
      if self.class.meta_conversion_enabled?(@setting)
        @meta_click_data = self.class.coerce_meta_click_hash(meta_click_data)
        @client_context = client_context.is_a?(Hash) ? client_context : {}
        explicit = ::CampaignAttributionHelper.normalize(campaign_attribution)
        @campaign_attribution = explicit.presence || ::CampaignAttributionHelper.from_note_attributes(order)
      else
        @meta_click_data = {}
        @client_context = {}
        @campaign_attribution = {}
      end
    end

    def self.call(order, updated_amount, setting = nil)
      new(order, updated_amount, setting).sync_partial_payment
    end

    # When +meta_click_data+ and +client_context+ are both nil, pass +shop+ (and optional
    # +fallback_order+) so click IDs are loaded from order note attributes via
    # MetaClickContextService — same as PartialOrderEditJob used to do before calling
    # this class. If either hash is present, auto-fetch is skipped (e.g. COD form params).
    def self.call_with_context(order, updated_amount, setting = nil, meta_click_data: nil, client_context: nil, shop: nil, fallback_order: nil)
      if shop.present? && meta_click_data.nil? && client_context.nil?
        meta_click_data, client_context = ::MetaClickContextService.fetch_for_capi(shop, order: order, fallback_order: fallback_order)
        session_id = ::MetaClickContextService.codk_session_id_from_shopify_order(order)
        session_id = ::MetaClickContextService.codk_session_id_from_shopify_order(fallback_order) if session_id.blank? && fallback_order
        Rails.logger.info(
          "[Codk::PartialPayment] Meta CAPI remaining_balance session_id=#{session_id.present? ? 'present' : 'missing'} " \
            "fbp=#{meta_click_data['fbp'].present?} fbc=#{meta_click_data['fbc'].present?} " \
            "event_source_url=#{client_context['event_source_url'].present?}"
        )
      end
      new(order, updated_amount, setting, meta_click_data: meta_click_data, client_context: client_context,
          campaign_attribution: nil).sync_partial_payment
    end

    # Sends a Purchase event for the full order total (e.g. when order is placed via COD form).
    def self.call_purchase(order, setting = nil, meta_click_data: nil, client_context: nil, campaign_attribution: nil)
      total = order.respond_to?(:total_price) ? order.total_price.to_s.to_f : 0
      new(order, total, setting, meta_click_data: meta_click_data, client_context: client_context,
          campaign_attribution: campaign_attribution).sync_purchase
    end

    def sync_partial_payment
      sync_event(event_id_suffix: "remaining_balance")
    end

    def sync_purchase
      sync_event(event_id_suffix: "purchase")
    end

    def sync_event(event_id_suffix:)
      return { "skipped" => true, "reason" => "meta_conversion_disabled" } unless self.class.meta_conversion_enabled?(@setting)
      return { "error" => "Pixel ID and Pixel Token not configured" } if @pixel_id.blank? || @access_token.blank?

      url = URI("https://graph.facebook.com/#{API_VERSION}/#{@pixel_id}/events?access_token=#{@access_token}")

      custom_data = build_custom_data
      # Deterministic event_id so Meta can deduplicate and attribute server + browser events
      event_id = "order_#{@order.id}_#{event_id_suffix}"

      user_data = {
        em: [Digest::SHA256.hexdigest(@order.email.to_s.downcase.strip)],
        external_id: [@order.id.to_s]
      }

      ph_hashes = hashed_ph_param
      user_data[:ph] = ph_hashes if ph_hashes.present?

      fbp = ascii_only((@meta_click_data["fbp"] || @meta_click_data[:fbp]).to_s).strip
      fbc = ascii_only((@meta_click_data["fbc"] || @meta_click_data[:fbc]).to_s).strip
      user_data[:fbp] = fbp if fbp.present?
      user_data[:fbc] = fbc if fbc.present?

      # Optional, improves match quality when available
      client_ip = ascii_only((@client_context["client_ip_address"] || @client_context[:client_ip_address]).to_s).strip
      client_ua = ( @client_context["client_user_agent"] || @client_context[:client_user_agent] ).to_s
      user_data[:client_ip_address] = client_ip if client_ip.present?
      user_data[:client_user_agent] = client_ua if client_ua.present?

      event_source_url = ( @client_context["event_source_url"] || @client_context[:event_source_url] ).to_s

      payload = {
        data: [{
          event_name: "Purchase",
          event_time: Time.now.to_i,
          action_source: "website",
          event_id: event_id,
          event_source_url: event_source_url.presence,
          user_data: user_data,
          custom_data: custom_data
        }]
      }
      payload[:test_event_code] = ascii_only(@setting&.pixel_test_event_id.to_s).strip if @setting&.pixel_test_event_id.present?

      payload_json = JSON.pretty_generate(payload)
      Rails.logger.info("MetaConversionService payload (order=#{@order.id}, suffix=#{event_id_suffix}): #{payload_json}")

      response = Net::HTTP.post(url, payload.to_json, "Content-Type" => "application/json")
      parsed = JSON.parse(response.body)
      parsed["_payload"] = payload
      parsed["_payload_json_truncated"] = truncate_for_slack(payload_json)
      parsed
    rescue StandardError => e
      Rails.logger.error "MetaConversionService error: #{e.message}"
      { "error" => e.message }
    end

    private

    def build_custom_data
      currency = (@order.respond_to?(:currency) && @order.currency.presence) || "INR"
      data = {
        value: @updated_amount.to_f,
        currency: currency,
        order_id: @order.id.to_s
      }
      # Add content fields so server event format matches browser pixel; helps Meta aggregate by order_id
      contents, content_ids, num_items = build_content_fields
      data[:contents] = contents if contents.present?
      data[:content_ids] = content_ids if content_ids.present?
      data[:content_type] = "product_group" if content_ids.present?
      data[:num_items] = num_items if num_items && num_items.positive?
      ::CampaignAttributionHelper.apply_to_meta_custom_data!(data, @campaign_attribution)
      data
    end

    def build_content_fields
      return [nil, nil, nil] unless @order.respond_to?(:line_items) && @order.line_items.present?

      # Only include line items that are fulfillable (exclude refunded/zeroed partial-payment lines).
      # Also exclude descriptive lines (e.g. "Partial Payment for..." in title).
      eligible = @order.line_items.select do |li|
        next false if li.respond_to?(:fulfillable_quantity) && li.fulfillable_quantity.to_i.zero?
        title = [li.respond_to?(:title) ? li.title : nil, li.respond_to?(:name) ? li.name : nil].compact.join(" ")
        next false if title.include?("Partial Payment for")
        id = li.respond_to?(:product_id) ? li.product_id.to_s : (li.respond_to?(:id) ? li.id.to_s : nil)
        !id.blank?
      end

      contents = []
      content_ids = []
      num_items = 0
      eligible.each do |li|
        id = (li.respond_to?(:product_id) ? li.product_id.to_s : li.id.to_s)
        qty = (li.respond_to?(:quantity) ? li.quantity : 1).to_i
        price = (li.respond_to?(:price) ? li.price : 0).to_s.to_f
        content_ids << id
        num_items += qty
        contents << { id: id, quantity: qty, item_price: price }
      end

      [contents.presence, content_ids.presence, num_items.positive? ? num_items : nil]
    end

    def raw_phone_for_meta
      o = @order
      return nil unless o

      %i[shipping_address billing_address].each do |meth|
        next unless o.respond_to?(meth)
        addr = o.public_send(meth)
        next if addr.blank?
        p = if addr.respond_to?(:phone)
              addr.phone
            elsif addr.is_a?(Hash)
              addr[:phone] || addr["phone"]
            end
        return p if p.to_s.strip.present?
      end

      if o.respond_to?(:customer) && o.customer
        cu = o.customer
        if cu.respond_to?(:phone) && cu.phone.to_s.strip.present?
          return cu.phone
        end
      end

      mp = @meta_click_data["phone"] || @meta_click_data[:phone]
      return mp if mp.to_s.strip.present?

      nil
    end

    # Meta CAPI: normalize to digits (include country code), then SHA-256 hexdigest.
    def hashed_ph_param
      phone = raw_phone_for_meta
      return nil if phone.to_s.strip.blank?

      digits = phone.to_s.gsub(/\D/, "")
      return nil if digits.length < 8
      return nil if digits.length > 15

      [Digest::SHA256.hexdigest(digits)]
    end

    def ascii_only(str)
      str.encode(Encoding::ASCII, invalid: :replace, undef: :replace, replace: "").strip
    end

    def truncate_for_slack(str)
      s = str.to_s
      return s if s.length <= SLACK_PAYLOAD_TRUNCATE_CHARS
      "#{s[0, SLACK_PAYLOAD_TRUNCATE_CHARS]}…(truncated)"
    end
  end
end
