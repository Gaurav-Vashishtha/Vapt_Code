# frozen_string_literal: true

module Whatsapp
  module Ai
    class DiscountGranter
      PREFIX = 'AI'

      def self.call(conversation:, setting:, cart:, dry_run: false)
        new(conversation, setting, cart, dry_run).call
      end

      def initialize(conversation, setting, cart, dry_run)
        @conversation = conversation
        @setting = setting
        @cart = cart.is_a?(Hash) ? cart : {}
        @dry_run = dry_run
        @shop = conversation.shop
      end

      def call
        config = @setting.discount_config
        return error('Discounts are not enabled.') unless @setting.skill?('discounts')

        existing = @conversation.ai_discount.is_a?(Hash) ? @conversation.ai_discount : nil
        if existing.present?
          return existing.merge('ok' => true, 'reused' => true) if Time.zone.parse(existing['expires_at'].to_s)&.future?

          return error('This customer already received their one discount.')
        end

        total = @cart['total'].to_s.gsub(/[^\d.]/, '').to_f
        minimum = config['min_cart_value'].to_f
        if minimum.positive? && total.positive? && total < minimum
          return error("The cart is below the minimum value for a discount (#{minimum}). Tell the customer the code works on orders above it.")
        end

        percent = config['max_percent'].to_f
        return error('Discounts are not configured.') unless percent.positive?

        expires_at = config['expiry_hours'].to_i.clamp(1, 168).hours.from_now
        code = "#{PREFIX}#{SecureRandom.alphanumeric(6).upcase}"
        return grant(code, percent, expires_at, test: true) if @dry_run

        create_price_rule!(code, percent, expires_at, minimum)
        grant(code, percent, expires_at)
      rescue StandardError => e
        Rails.logger.error("[Whatsapp::Ai::DiscountGranter] conv=#{@conversation.id} #{e.class}: #{e.message}")
        error('Could not create a discount right now. Do not promise one.')
      end

      private

      def grant(code, percent, expires_at, test: false)
        value = percent == percent.round ? percent.round.to_s : format('%.1f', percent)
        result = {
          'ok' => true,
          'code' => test ? "#{code} (test)" : code,
          'formatted' => "#{value}% off",
          'link' => discount_link(code),
          'expires_at' => expires_at.iso8601,
          'valid_for_hours' => ((expires_at - Time.current) / 3600.0).round,
          'minimum_order' => @setting.discount_config['min_cart_value'].to_f.positive? ? @setting.discount_config['min_cart_value'] : nil
        }.compact
        unless test || !@conversation.persisted?
          WhatsappConversation.where(id: @conversation.id).update_all(ai_discount: result.except('ok'), updated_at: Time.current)
          @conversation.ai_discount = result.except('ok')
        end
        result
      end

      def create_price_rule!(code, percent, expires_at, minimum)
        @shop.init_session
        attrs = {
          title: code,
          target_type: 'line_item',
          target_selection: 'all',
          allocation_method: 'across',
          customer_selection: 'all',
          value_type: 'percentage',
          value: -percent,
          starts_at: Time.now.utc.iso8601,
          ends_at: expires_at.utc.iso8601,
          usage_limit: 1,
          once_per_customer: true
        }
        attrs[:prerequisite_subtotal_range] = { greater_than_or_equal_to: minimum.to_s } if minimum.positive?
        price_rule = ::ShopifyAPI::PriceRule.create(attrs)
        raise "price rule not created: #{price_rule.errors.full_messages.join(', ')}" if price_rule.id.blank?

        discount = ::ShopifyAPI::DiscountCode.create(price_rule_id: price_rule.id, code: code)
        raise "discount code not created: #{discount.errors.full_messages.join(', ')}" if discount.id.blank?
      end

      def discount_link(code)
        url = @cart['checkout_url'].to_s
        uri = url.present? ? URI.parse(url) : nil
        if uri&.host.present?
          "https://#{uri.host}/discount/#{code}?redirect=#{CGI.escape(uri.request_uri)}"
        else
          host = @shop.primary_domain.to_s.sub(%r{\Ahttps?://}, '').split('/').first.presence || @shop.shopify_domain
          "https://#{host}/discount/#{code}"
        end
      rescue URI::InvalidURIError
        nil
      end

      def error(message)
        { 'ok' => false, 'error' => message }
      end
    end
  end
end
