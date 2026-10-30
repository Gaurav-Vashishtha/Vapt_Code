# frozen_string_literal: true

module Whatsapp
  module Inbox
    module OrderLookup
      LAST10_SQL = ::Whatsapp::ContactOrderStats::ORDER_LAST10
      EXCLUDED_STATUSES = ::Whatsapp::ContactOrderStats::EXCLUDED_STATUSES
      CONFIRMED_STATUSES = %w[COD-Verified COD-Manual-Verified].freeze
      CANCELLED_STATUSES = %w[COD-Cancelled COD-Auto-Cancelled COD-AUTO-CANCELLED].freeze
      MIN_DIGITS = 8

      # order_amount is free text ("1,299.00", "Rs. 500"); take the first number so a
      # stray character never aborts the whole SUM with a cast error.
      AMOUNT_SQL = "NULLIF(substring(replace(order_confirmations.order_amount, ',', '') from '[0-9]+(?:\\.[0-9]+)?'), '')::numeric"

      module_function

      def last10(raw)
        raw.to_s.gsub(/\D/, '').last(10)
      end

      def scope(shop, phone_last10)
        digits = last10(phone_last10)
        return OrderConfirmation.none if shop.nil? || digits.length < MIN_DIGITS

        OrderConfirmation
          .where(shop_id: shop.id)
          .where("#{LAST10_SQL} = ?", digits)
          .where('order_confirmations.status IS NULL OR order_confirmations.status NOT IN (?)', EXCLUDED_STATUSES)
      end

      def recent(shop, phone_last10, limit: 5)
        scope(shop, phone_last10).order(created_at: :desc, id: :desc).limit(limit).to_a
      end

      def latest(shop, phone_last10)
        recent(shop, phone_last10, limit: 1).first
      end

      def lifetime(shop, phone_last10)
        count, value, currency = scope(shop, phone_last10).pick(
          Arel.sql('COUNT(*)'),
          Arel.sql("COALESCE(SUM(#{AMOUNT_SQL}), 0)"),
          Arel.sql('(array_agg(order_confirmations.currency ORDER BY order_confirmations.created_at DESC) ' \
                   "FILTER (WHERE order_confirmations.currency IS NOT NULL AND order_confirmations.currency <> ''))[1]")
        )
        { orders: count.to_i, value: BigDecimal((value || 0).to_s), currency: currency.presence }
      end

      def find_by_order_number(shop, term)
        number = term.to_s.strip.delete_prefix('#').strip
        return [] if shop.nil? || number.blank? || number.length > 40

        OrderConfirmation
          .where(shop_id: shop.id, order_number: [number, "##{number}"])
          .where.not(customer_number: [nil, ''])
          .limit(20)
          .pluck(Arel.sql(LAST10_SQL))
          .select { |d| d.to_s.length >= MIN_DIGITS }
          .uniq
      end

      def status_key(order_confirmation)
        status = order_confirmation.status.to_s
        if CONFIRMED_STATUSES.include?(status)
          'confirmed'
        elsif ::Whatsapp::ContactOrderStats::UNCONFIRMED_COD_STATUSES.include?(status)
          'awaiting_confirmation'
        elsif ::Whatsapp::ContactOrderStats::PREPAID_STATUSES.include?(status)
          'paid_online'
        elsif CANCELLED_STATUSES.include?(status)
          'cancelled'
        else
          'other'
        end
      end

      def status_label(order_confirmation)
        return '' if order_confirmation.nil?

        key = status_key(order_confirmation)
        raw = order_confirmation.status.to_s
        base = I18n.t("whatsapp_inbox.order_status.#{key}",
                      status: raw.tr('-_', '  ').squish,
                      default: key == 'other' ? raw.tr('-_', '  ').squish : key.humanize)
        shipping = shipping_label(order_confirmation.shipping_status)
        [base.presence, shipping].compact.join(' · ')
      end

      def shipping_label(shipping_status)
        value = shipping_status.to_s.strip
        return nil if value.blank?
        return I18n.t('whatsapp_inbox.order_status.rto', default: 'Returned to origin') if value.match?(/\brto\b/i)

        value.tr('-_', '  ').squish.capitalize
      end
    end
  end
end
