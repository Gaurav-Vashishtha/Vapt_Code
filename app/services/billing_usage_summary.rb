# frozen_string_literal: true

class BillingUsageSummary
  attr_reader :shop, :days

  MAX_DAYS = 90
  DEFAULT_DAYS = 30
  BUCKET_COUNT = 4
  CURRENT_TIME = -> { Time.zone.now }.freeze

  SMS_CATEGORY_CONFIG = {
    verification: {
      type: :twilio,
      ver_types: ["SMS"]
    },
    confirmation: {
      type: :twilio,
      ver_types: ["Confirmation-SMS"]
    },
    fulfilment: {
      type: :twilio,
      ver_types: ["Fulfilment-SMS"]
    },
    pre_order: {
      type: :pre_order,
      ver_type: "SMS"
    },
    abandoned_cart: {
      type: :abandoned_cart,
      notif_type: "SMS"
    }
  }.freeze

  WHATSAPP_CATEGORY_CONFIG = {
    whatsapp: {
      type: :twilio,
      ver_types: ["WHATSAPP"]
    },
    whatsapp_cod_prepaid: {
      type: :twilio,
      ver_types: ["WHATSAPP_COD_PREPAID"]
    },
    whatsapp_first_purchase: {
      type: :twilio,
      ver_types: ["WHATSAPP_FIRST_PURCHASE"]
    },
    whatsapp_confirmation: {
      type: :twilio,
      ver_types: ["WHATSAPP-CONFIRMATION"]
    },
    whatsapp_fulfilment: {
      type: :twilio,
      ver_types: ["WHATSAPP-FULFILMENT"]
    },
    pre_order: {
      type: :pre_order,
      ver_type: "WHATSAPP"
    },
    abandoned_cart: {
      type: :abandoned_cart,
      notif_type: "WHATSAPP"
    },
    # Branded WhatsApp (merchant's own number): our flat per-message commission.
    bsp: {
      type: :bsp
    }
  }.freeze

  def initialize(shop:, days: nil, start_date: nil, end_date: nil)
    @shop = shop
    if start_date.present? && end_date.present?
      @start_date = Date.parse(start_date)
      @end_date = Date.parse(end_date)
      @days = nil
    else
      @days = sanitize_days(days)
      @start_date = nil
      @end_date = nil
    end
  end

  def as_json(*)
    sms_summary = summarize_categories(SMS_CATEGORY_CONFIG)
    whatsapp_summary = summarize_categories(WHATSAPP_CATEGORY_CONFIG)
    transaction_summary = aggregate_transactions(start_time, end_time)

    result = {
      timeframe: {
        days: days,
        since: start_time,
        until: end_time,
        label: timeframe_label
      },
      sms: transform_keys_to_camel_case(sms_summary),
      whatsapp: transform_keys_to_camel_case(whatsapp_summary),
      transaction: transaction_summary,
      totals: {
        sms: aggregate_totals_from_summary(sms_summary),
        whatsapp: aggregate_totals_from_summary(whatsapp_summary),
        transaction: transaction_summary
      },
      breakdown: breakdown_rows
    }
    
    result
  end

  private

  def sanitize_days(value)
    parsed = value.to_i
    parsed = DEFAULT_DAYS if parsed <= 0
    [parsed, MAX_DAYS].min
  end

  def start_time
    @start_time ||= if @start_date
                      @start_date.beginning_of_day
                    else
                      days.days.ago.beginning_of_day
                    end
  end

  def end_time
    @end_time ||= if @end_date
                    @end_date.end_of_day
                  else
                    CURRENT_TIME.call
                  end
  end

  def timeframe_label
    if @start_date && @end_date
      "#{@start_date.strftime('%b %d, %Y')} - #{@end_date.strftime('%b %d, %Y')}"
    elsif days
      "Last #{days} days"
    else
      "Custom range"
    end
  end

  def bucket_ranges
    return @bucket_ranges if defined?(@bucket_ranges)

    total_days = if @start_date && @end_date
                   (@end_date - @start_date).to_i + 1
                 else
                   days
                 end

    bucket_span_days = [(total_days.to_f / BUCKET_COUNT).ceil, 1].max
    ranges = []
    range_end = end_time

    BUCKET_COUNT.times do
      range_start = [range_end - bucket_span_days.days, start_time].max
      start_label = range_start.strftime("%b %d, %Y")
      end_label = range_end.strftime("%b %d, %Y")
      ranges << {
        start: range_start,
        end: range_end,
        label: "#{start_label} - #{end_label}"
      }
      range_end = range_start
      break if range_end <= start_time
    end

    @bucket_ranges = ranges.reverse
  end

  def round_amount(value)
    return 0.0 unless value

    value.to_f.round(4)
  end

  def breakdown_rows
    bucket_ranges.map do |range|
      sms_total = aggregate_category_group(
        SMS_CATEGORY_CONFIG,
        range_start: range[:start],
        range_end: range[:end]
      )
      whatsapp_total = aggregate_category_group(
        WHATSAPP_CATEGORY_CONFIG,
        range_start: range[:start],
        range_end: range[:end]
      )
      transaction_total = aggregate_transactions(range[:start], range[:end])

      total_amount = sms_total[:amount].to_f +
                     whatsapp_total[:amount].to_f +
                     transaction_total[:amount].to_f

      {
        label: range[:label],
        range: { start: range[:start], end: range[:end] },
        sms: sms_total,
        whatsapp: whatsapp_total,
        transaction: transaction_total,
        total: {
          amount: round_amount(total_amount)
        }
      }
    end
  end

  def aggregate_category_group(configs, range_start:, range_end:)
    configs.each_value.reduce({ count: 0, amount: 0.0 }) do |memo, category|
      data = aggregate_category(category, range_start: range_start, range_end: range_end)
      memo[:count] += data[:count].to_i
      memo[:amount] += data[:amount].to_f
      memo
    end.then do |result|
      {
        count: result[:count],
        amount: round_amount(result[:amount])
      }
    end
  end

  def aggregate_transactions(range_start, range_end)
    records = shop.order_confirmations
                  .where(status: "COD-Partial-Payment-Received")
                  .where(is_prepaid_charged: true)
                  .where("updated_at >= ? AND updated_at <= ?", range_start, range_end)

    {
      count: records.count,
      amount: round_amount(records.sum(:cod_fee))
    }
  end

  def summarize_categories(configs)
    configs.each_with_object({}) do |(key, config), memo|
      memo[key] = aggregate_category(config, range_start: start_time, range_end: end_time)
    end
  end

  def aggregate_category(config, range_start:, range_end:)
    scope, timestamp_column = scope_for(config)

    scoped = scope
             .where("#{timestamp_column} >= ?", range_start)
             .where("#{timestamp_column} <= ?", range_end)

    {
      count: scoped.count,
      amount: round_amount(scoped.sum(:actual_charge_applied))
    }
  end

  def scope_for(config)
    case config[:type]
    when :twilio
      [
        TwilioLog.where(
          shop_id: shop.id,
          status: "SUCCESS",
          ver_type: config[:ver_types]
        ),
        :created_at
      ]
    when :abandoned_cart
      [
        AbandonedCart.where(
          shop_id: shop.id,
          status: "SUCCESS",
          notif_type: config[:notif_type]
        ),
        :updated_at
      ]
    when :pre_order
      scope = PreOrderOtp.where(
        shop_id: shop.id,
        status: true,
        is_charged: true
      )
      # Filter by ver_type if specified in config
      if config[:ver_type].present?
        scope = scope.where(ver_type: config[:ver_type])
      end
      [
        scope,
        :updated_at
      ]
    when :bsp
      [
        WhatsappMessageLog.where(shop_id: shop.id, status: %i[sent delivered read]),
        :created_at
      ]
    else
      raise ArgumentError, "Unknown category type: #{config[:type]}"
    end
  end

  def aggregate_totals_from_summary(summary_hash)
    summary_hash.values.reduce({ count: 0, amount: 0.0 }) do |memo, data|
      memo[:count] += data[:count].to_i
      memo[:amount] += data[:amount].to_f
      memo
    end.then do |result|
      {
        count: result[:count],
        amount: round_amount(result[:amount])
      }
    end
  end

  def transform_keys_to_camel_case(hash)
    hash.transform_keys { |key| key.to_s.camelize(:lower).to_sym }
  end
end

