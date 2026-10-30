class OrderConfirmation < ApplicationRecord
  belongs_to :shop
  has_one_time_password length: 4

  has_many :twilio_logs, dependent: :destroy

  # Post-order OTP derived from the order itself, so every job that saves the
  # same order (webhook, SQS, thank-you page fetch, partial-payment trigger)
  # lands on the same code — a second run can never invalidate an SMS already
  # sent. Uses only shop id + Shopify order id (the order number is formatted
  # differently across paths: 1001 vs "#1001"). Keyed with a server secret so
  # the code can't be computed from the order id visible in URLs.
  # Same range as before: 1111..9998.
  def self.derived_otp(shop_id, order_id)
    secret = ENV['ORDER_OTP_SECRET'].presence || Rails.application.secret_key_base
    digest = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{shop_id}:#{order_id.to_s.strip}")
    (1111 + (digest[0, 15].to_i(16) % 8888)).to_s
  end

  scope :with_logs, -> { where.not(status: 'Non-COD').includes(:twilio_logs).order(id: :desc) }

  # scope :last_2_months, lambda { { conditions: { created_at: last_2_months_range } } }
  scope :last_2_months, -> { where(created_at: last_2_months_range).order(created_at: :desc) }

  scope :since, ->(time = 4.hours.ago) { where('created_at > ?', time) }

  scope :verified, -> { where(status: 'COD-Verified') }
  scope :pending, -> { where(status: 'Pending') }
  scope :non_cod, -> { where(status: 'Non-COD') }
  scope :missing_shipping_status, -> { where(shipping_status: [nil, ""]) }

  def self.last_2_months_range
    2.month.ago.utc.beginning_of_month..DateTime.now
  end

  def self.to_csv
    attributes = %w[order_id order_number currency order_amount customer_name customer_number otp_status order_date
                    order_time]

    CSV.generate(headers: true) do |csv|
      csv << attributes

      all.each do |order_confirmation|
        csv << attributes.map { |attr| order_confirmation.send(attr) }
      end
    end
  end

  def is_cod(params)
    #TODO line items logic
    if !shop.setting.post_order_include_product_ids.blank?
      params['line_items'].each do |line_item|
        config_product_ids = shop.setting.post_order_include_product_ids.split(',')
        if (!line_item['product_id'].blank?) && (config_product_ids.include? line_item['product_id'])
          return true
        end
      end
    end
    # treat COD if payment gateways not found
    if shop.cod_include_tags=='*'
      return true
    end
    return true if params['gateway'].blank? && params['payment_gateway_names'].blank?
    return true if params['gateway']=='bogus' || params['payment_gateway_names']=='bogus'
    
    return false if params['financial_status'] == 'paid'

    # Build list of gateways by combining 2 params (guard nil so we don't call + on nil)
    payment_gateway_names = Array(params['payment_gateway_names'])
    payment_gateways = (payment_gateway_names + [params['gateway']]).uniq.select(&:present?).map(&:downcase)

    # Non COD (return false) if any gateway in exclusion list
    exclude_tags = shop.cod_exclude_tags.present? ? shop.cod_exclude_tags.split(',').map(&:strip) : []
    return false if exclude_tags.any? { |tag| payment_gateways.include?(tag.to_s.downcase) }

    include_tags = shop.cod_include_tags.present? ? shop.cod_include_tags.split(',').map(&:strip) : []
    return true if include_tags.any? { |tag| payment_gateways.any? { |gateway| gateway.include?(tag.to_s) } }

    false
  end

  def get_country_code(params)
    params.dig('shipping_address',
               'country_code') || params.dig('billing_address',
                                             'country_code') || params.dig('customer', 'default_address',
                                                                           'country_code')
  end

  # Synthetic id from SettingsController#test_notification (`order_confirmation` / first-purchase tests).
  TEST_NOTIFICATION_ORDER_ID = "1234567890".freeze
  TEST_NOTIFICATION_SMS_ORDER_NUMBER = "1234".freeze

  def final_order_number
    final_order_number=order_number
    if order_number.blank?
      final_order_number = order_id
    end
    if !order_number.blank? &&  !shop.setting.order_number_prefix.blank?
      final_order_number = shop.setting.order_number_prefix + order_number
    end
    if !order_number.blank? &&  !shop.setting.order_number_suffix.blank?
      final_order_number = final_order_number + shop.setting.order_number_suffix
    end
    return final_order_number
  end

  # Order number shown in SMS/WhatsApp templates (short placeholder for test orders).
  def customer_facing_order_number
    order_id.to_s == TEST_NOTIFICATION_ORDER_ID ? TEST_NOTIFICATION_SMS_ORDER_NUMBER : final_order_number
  end

  def sms_count
    twilio_logs.size.to_s
  end

  def otp_status
    return 'COD-Pending' if status === 'Pending'

    status
  end

  def order_date
    begin
      zone = shop.owner_timezone.split(' ').last
    rescue StandardError => e
      zone = 'America/New_York'
    end
    created_at.in_time_zone(zone).strftime('%b %e, %Y')
  end

  def order_time
    begin
      zone = shop.owner_timezone.split(' ').last
    rescue StandardError => e
      zone = 'America/New_York'
    end
    created_at.in_time_zone(zone).strftime('%I:%M %p')
  end
end
