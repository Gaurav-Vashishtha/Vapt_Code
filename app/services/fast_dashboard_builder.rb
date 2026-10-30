# frozen_string_literal: true

# Composes a shop's core merchant metrics for a rolling window_days window into
# a single cached payload backing analytics#fast_dashboard. Reuses the same
# OrderConfirmation / Twilio / AbandonedCart aggregation the individual analytics
# actions use, but over the whole window (single grouped queries, no per-day
# loops). Billing is intentionally excluded — it makes a live Shopify HTTP call.
class FastDashboardBuilder
  DEFAULT_WINDOW_DAYS = 30
  TTL = 10.minutes

  UNDELIVERED_KEYS = %w[undelivered failure failed restock restocked mark marked].freeze

  def self.call(shop:, window_days: DEFAULT_WINDOW_DAYS, refresh: false)
    new(shop: shop, window_days: window_days, refresh: refresh).call
  end

  def self.funnel_for(shop:, window_days: DEFAULT_WINDOW_DAYS)
    new(shop: shop, window_days: window_days).funnel
  end

  def initialize(shop:, window_days: DEFAULT_WINDOW_DAYS, refresh: false)
    @shop = shop
    @window_days = window_days.to_i
    @window_days = DEFAULT_WINDOW_DAYS unless @window_days.positive?
    @refresh = refresh
    @from_time = @window_days.days.ago.beginning_of_day
    @to_time = Time.current.end_of_day
  end

  def call
    snapshot = SummarySnapshot.find_by(shop_id: @shop.id, window_days: @window_days)

    if !@refresh && snapshot && fresh?(snapshot)
      return snapshot.payload.deep_symbolize_keys.merge(cached: true)
    end

    payload = build_payload
    persist(payload)
    payload.merge(cached: false)
  end

  def funnel
    events = FormFunnelEvent.where(shop_id: @shop.id, occurred_at: @from_time..@to_time)
    {
      sessions: events.where(event_type: 'form_view').distinct.count(:session_token),
      checkout_initiated: events.where(event_type: 'checkout_initiated').distinct.count(:session_token),
      otp_verified: PreOrderOtp.where(shop_id: @shop.id, status: true, created_at: @from_time..@to_time).count,
      orders_placed: orders.count
    }
  end

  private

  def fresh?(snapshot)
    snapshot.computed_at.present? && snapshot.computed_at >= TTL.ago
  end

  def build_payload
    computed_at = Time.current
    total_orders = orders.count
    revenue_total = amount_sum(orders)
    orders_with_amount = orders.where.not(order_amount: [nil, '']).count

    {
      window_days: @window_days,
      revenue: { total: revenue_total, currency: currency_symbol },
      aov: orders_with_amount.positive? ? (revenue_total / orders_with_amount).round(2) : 0.0,
      orders: {
        total: total_orders,
        cod: orders.where(is_cod_order: true).count,
        prepaid: orders.where(is_cod_order: false).count,
        verified: orders.where(status: 'COD-Verified').count
      },
      partial_payment: partial_payment_metrics,
      cod_to_prepaid: cod_to_prepaid_metrics,
      funnel: funnel,
      messages: message_metrics,
      rto: rto_metrics,
      features: feature_flags,
      computed_at: computed_at.iso8601
    }
  end

  def persist(payload)
    snapshot = SummarySnapshot.find_or_initialize_by(shop_id: @shop.id, window_days: @window_days)
    snapshot.payload = payload
    snapshot.computed_at = Time.current
    snapshot.save!
  rescue StandardError => e
    Rails.logger.warn("[FastDashboard] persist failed shop_id=#{@shop.id} #{e.class}: #{e.message}")
    nil
  end

  def orders
    @orders ||= OrderConfirmation
                .where(shop_id: @shop.id, created_at: @from_time..@to_time)
                .where.not(status: 'Test-Order')
  end

  def amount_sum(scope)
    scope.where.not(order_amount: [nil, ''])
         .pluck(:order_amount)
         .map(&:to_f)
         .sum
         .round(2)
  end

  def partial_payment_metrics
    scope = orders.where(status: 'COD-Partial-Payment-Received')
    { count: scope.count, value: amount_sum(scope) }
  end

  def cod_to_prepaid_metrics
    scope = orders.where(status: 'COD-Prepaid')
    { count: scope.count, value: amount_sum(scope) }
  end

  def message_metrics
    sms = 0
    whatsapp = 0

    TwilioLog.where(shop_id: @shop.id, created_at: @from_time..@to_time)
             .group(:ver_type, :status).count.each do |(ver_type, _status), count|
      channel = detect_channel(ver_type)
      next unless channel

      channel == :sms ? sms += count : whatsapp += count
    end

    pre_order = PreOrderOtp.otp_sends.where(shop_id: @shop.id, created_at: @from_time..@to_time).count
    sms += pre_order

    AbandonedCart.where(shop_id: @shop.id, created_at: @from_time..@to_time)
                 .group(:notif_type, :status).count.each do |(notif_type, _status), count|
      channel = detect_channel(notif_type)
      next unless channel

      channel == :sms ? sms += count : whatsapp += count
    end

    abandoned_cart_sent = AbandonedCart.where(shop_id: @shop.id, created_at: @from_time..@to_time).count

    {
      total_sent: sms + whatsapp,
      sms: sms,
      whatsapp: whatsapp,
      abandoned_cart_sent: abandoned_cart_sent
    }
  end

  def detect_channel(type)
    return :sms if type.to_s.downcase.include?('sms')
    return :whatsapp if type.to_s.downcase.include?('whatsapp')

    nil
  end

  def rto_metrics
    by_status = Hash.new(0)
    orders.where.not(shipping_status: [nil, ''])
          .pluck(:shipping_status).each do |status|
      key = status.to_s.strip.downcase
      next if key.blank?

      by_status[key] += 1
    end

    delivered = by_status['delivered']
    rto = by_status['rto']
    undelivered = UNDELIVERED_KEYS.sum { |k| by_status[k] }
    total = delivered + rto + undelivered

    {
      delivered_pct: total.positive? ? ((delivered.to_f / total) * 100).round(1) : nil,
      rto_pct: total.positive? ? ((rto.to_f / total) * 100).round(1) : nil,
      undelivered_pct: total.positive? ? ((undelivered.to_f / total) * 100).round(1) : nil
    }
  end

  def feature_flags
    setting = @shop.setting
    {
      otp: bool(setting&.enable_pre_order_otp),
      partial_payment: bool(setting&.partial_payment_enabled),
      cod_fee: bool(setting&.cod_fee_enabled),
      prepaid_discount: bool(setting&.prepaid_enabled),
      abandoned_cart: bool(setting&.abandoned_cart_enabled),
      sms: bool(setting&.sms),
      whatsapp: bool(setting&.confirmation_whatsapp || setting&.fulfilment_whatsapp || setting&.ac_whatsapp),
      cod_form: bool(setting&.cod_form_enabled)
    }
  end

  def bool(value)
    value == true
  end

  def currency_symbol
    currency_code = @shop&.currency || 'INR'
    Money::Currency.find(currency_code)&.symbol || currency_code
  end
end
