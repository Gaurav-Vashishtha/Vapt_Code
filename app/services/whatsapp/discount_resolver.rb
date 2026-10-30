module Whatsapp
  # Resolves the discount that should accompany a particular abandoned-cart
  # reminder send. Three modes:
  #
  #   - none  → returns nil (no discount variables surface in the template).
  #   - static → returns the merchant's hard-coded code + value.
  #   - auto   → creates (or reuses) a one-time-use Shopify PriceRule +
  #     DiscountCode for this (shop, checkout, stage). The generated code is
  #     cached on AbandonedCart.dynamic_config so stage N+1 can either reuse
  #     the same code or get a fresh one — depends on `discount_config[:reuse]`.
  #
  # Returns a hash matching the EventRegistry's `discount.*` paths so the
  # injected payload feeds VariableResolver directly. `value` is already
  # display-formatted per the discount kind — percent carries the % sign,
  # fixed carries the shop's currency symbol — so templates render correctly
  # whichever variable the merchant mapped:
  #   { 'code' => 'COMEBACK10', 'value' => '10%', 'formatted' => '10% off' }
  #   { 'code' => 'COMEBACK99', 'value' => '₹99', 'formatted' => '₹99 off' }
  class DiscountResolver
    Result = Struct.new(:code, :value, :formatted, :kind, keyword_init: true) do
      # Shape that goes back into the dispatch payload under the `discount`
      # key so the existing VariableResolver picks it up via the registry's
      # `path: 'discount.code'` etc.
      def to_payload_hash
        { 'code' => code, 'value' => value, 'formatted' => formatted, 'kind' => kind }
      end
    end

    # Number of days a generated discount code is valid for. Mirrors MSG91's
    # 24h window — short enough to nudge urgency, long enough that a buyer
    # who comes back the next day still finds it valid.
    DEFAULT_EXPIRY_HOURS = 24

    def self.call(shop:, abandoned_cart:, discount_config:, stage_index:)
      new(
        shop: shop,
        abandoned_cart: abandoned_cart,
        discount_config: discount_config,
        stage_index: stage_index
      ).call
    end

    def initialize(shop:, abandoned_cart:, discount_config:, stage_index:)
      @shop = shop
      @abandoned_cart = abandoned_cart
      @discount_config = (discount_config || {}).deep_stringify_keys
      @stage_index = stage_index
    end

    def call
      mode = discount_config['mode'].to_s
      return nil if mode.empty? || mode == 'none'

      case mode
      when 'static' then resolve_static
      when 'auto'   then resolve_auto
      else
        Rails.logger.warn("[discount_resolver] unknown mode=#{mode.inspect} stage=#{stage_index}")
        nil
      end
    end

    private

    attr_reader :shop, :abandoned_cart, :discount_config, :stage_index

    def resolve_static
      code  = discount_config['code'].to_s
      value = discount_config['value'].to_f
      kind  = discount_config['kind'].to_s.presence || 'percent'
      return nil if code.empty? || value <= 0
      Result.new(code: code, value: display_value(value, kind), formatted: format_for(value, kind), kind: kind)
    end

    def resolve_auto
      # If we've already generated a code for this stage on this cart, reuse
      # it. Without this cache the Shopify API would get hit on every retry
      # and the customer would see different codes across resends.
      cached = cached_code_for_stage
      if cached
        # Entries cached before value/formatted became display strings carry a
        # raw numeric `value` — re-format those so old carts still render with
        # the % / currency marker.
        cached_kind  = cached['kind']
        cached_value = cached['value']
        if cached_value.is_a?(Numeric)
          cached_value = display_value(cached_value, cached_kind)
          cached['formatted'] = format_for(cached['value'], cached_kind)
        end
        return Result.new(
          code: cached['code'],
          value: cached_value,
          formatted: cached['formatted'],
          kind: cached_kind
        )
      end

      value   = discount_config['value'].to_f
      kind    = discount_config['kind'].to_s.presence || 'percent'
      upto    = discount_config['upto'].to_f
      prefix  = discount_config['prefix'].to_s.presence || 'AC'
      expiry  = (discount_config['expiry_hours'].presence&.to_i || DEFAULT_EXPIRY_HOURS)
      return nil if value <= 0

      code = "#{prefix}#{SecureRandom.hex(3).upcase}"
      cart_total = abandoned_cart.respond_to?(:total_price) ? abandoned_cart.total_price.to_f : 0.0

      begin
        shop.init_session
        params = {
          title: code,
          target_type: 'line_item',
          target_selection: 'all',
          allocation_method: 'across',
          customer_selection: 'all',
          starts_at: Time.now.utc.iso8601,
          ends_at: expiry.hours.from_now.utc.iso8601,
          usage_limit: 1,
          once_per_customer: true
        }

        if kind == 'fixed'
          params.merge!(value_type: 'fixed_amount', value: -value)
        else
          # Percent — apply the upto cap by converting to a fixed amount when
          # the percent off the cart total would otherwise exceed it.
          calculated = (cart_total * value) / 100.0
          if upto > 0 && calculated > upto
            params.merge!(value_type: 'fixed_amount', value: -upto)
          else
            params.merge!(value_type: 'percentage', value: -value)
          end
        end

        price_rule = ::ShopifyAPI::PriceRule.create(params)
        ::ShopifyAPI::DiscountCode.create(price_rule_id: price_rule.id, code: code)

        result = Result.new(
          code: code,
          value: display_value(value, kind),
          formatted: format_for(value, kind),
          kind: kind
        )
        cache_code_for_stage(result)
        result
      rescue => e
        Rails.logger.warn("[discount_resolver] auto-gen failed shop=#{shop.id} cart=#{abandoned_cart&.id} stage=#{stage_index}: #{e.class}: #{e.message}")
        nil
      end
    end

    # Pull a previously-generated discount for this stage off the cart's
    # dynamic_config blob. Returns the hash or nil.
    def cached_code_for_stage
      return nil unless abandoned_cart.respond_to?(:dynamic_config)
      bag = abandoned_cart.dynamic_config
      bag = bag.is_a?(Array) ? (bag.first || {}) : (bag || {})
      bag.dig('bsp_discounts', stage_index.to_s)
    end

    # Persist the generated discount onto the cart so a retry of the same
    # stage reuses the same code instead of generating a fresh one and
    # leaking unredeemed price rules.
    def cache_code_for_stage(result)
      return unless abandoned_cart.respond_to?(:dynamic_config=)
      current =
        if abandoned_cart.dynamic_config.is_a?(Array)
          abandoned_cart.dynamic_config.first || {}
        else
          abandoned_cart.dynamic_config || {}
        end
      current['bsp_discounts'] ||= {}
      current['bsp_discounts'][stage_index.to_s] = result.to_payload_hash
      abandoned_cart.update_column(:dynamic_config, current)
    end

    def format_for(value, kind)
      "#{display_value(value, kind)} off"
    end

    # "10%" for percent discounts, "₹500" (shop currency symbol) for fixed.
    def display_value(value, kind)
      kind.to_s == 'fixed' ? "#{currency_symbol}#{trim_number(value)}" : "#{trim_number(value)}%"
    end

    # 10.0 → "10", 10.5 → "10.50" — avoids "10.0% off" while keeping paise-level
    # fixed amounts intact.
    def trim_number(value)
      value = value.to_f
      value == value.round ? value.round.to_s : format('%.2f', value)
    end

    # Symbol for the shop's currency; falls back to the ISO code (e.g. "AED")
    # when no symbol is known, and to nothing when the shop has no currency yet.
    def currency_symbol
      currency = shop.respond_to?(:currency) ? shop.currency.to_s : ''
      symbol = defined?(CurrencyHelper) ? CurrencyHelper.symbol_for(currency.presence) : nil
      symbol = currency if symbol.blank? || symbol == '¤'
      symbol
    rescue StandardError
      currency.to_s
    end
  end
end
