# frozen_string_literal: true

module Whatsapp
  module DispatchRelevance
    module_function

    def skip_reason(event_type_key, shop, payload)
      case EventRegistry.relevance(event_type_key)
      when :cod_unverified then cod_unverified_reason(shop, payload)
      when :not_customer_cancelled then customer_cancelled_reason(payload)
      when :not_reordered then reordered_reason(shop, payload)
      end
    end

    def cod_unverified_reason(shop, payload)
      order_id = payload.dig('order', 'id').to_s
      return 'no_order' if order_id.blank?

      oc = shop.order_confirmations.find_by(order_id: order_id)
      return 'no_order' unless oc
      return 'verified' if ReattemptRelevance.verified?(oc) || CodVerificationActions.terminal?(oc)
      return 'cancelled_in_shopify' if shopify_cancelled?(shop, order_id)

      nil
    end

    def shopify_cancelled?(shop, order_id)
      shop.init_session
      order = ShopifyAPI::Order.find(order_id)
      order.respond_to?(:cancelled_at) && order.cancelled_at.present?
    rescue ActiveResource::ResourceNotFound
      true
    rescue StandardError => e
      Rails.logger.info("[whatsapp/relevance] order lookup failed shop=#{shop.id} order=#{order_id}: #{e.class}: #{e.message}")
      false
    end

    def customer_cancelled_reason(payload)
      tags = payload.dig('order', 'tags')
      tags = tags.join(',') if tags.is_a?(Array)
      'customer_cancelled' if tags.to_s.include?(ShopifyJobs::OrderPostJob::CUSTOMER_CANCELLED_TAG)
    end

    def reordered_reason(shop, payload)
      order = payload['order'].is_a?(Hash) ? payload['order'] : {}
      order_id = order['id'].to_s
      return 'no_order' if order_id.blank?

      shopify = shopify_reordered?(shop, order)
      return shopify ? 'reordered' : nil unless shopify.nil?

      'reordered' if local_reordered?(shop, order)
    end

    def shopify_reordered?(shop, order)
      customer_id = order.dig('customer', 'id')
      return nil if customer_id.blank?

      shop.init_session
      customer = ShopifyAPI::Customer.find(customer_id)
      last_id = customer.respond_to?(:last_order_id) ? customer.last_order_id.to_s : ''
      return nil if last_id.blank?

      last_id != order['id'].to_s
    rescue StandardError => e
      Rails.logger.info("[whatsapp/relevance] customer lookup failed shop=#{shop.id}: #{e.class}: #{e.message}")
      nil
    end

    def local_reordered?(shop, order)
      oc = shop.order_confirmations.find_by(order_id: order['id'].to_s)
      phone = oc&.customer_number.to_s.gsub(/\D/, '').last(10)
      return false if phone.blank?

      shop.order_confirmations
          .where('created_at > ?', oc.created_at)
          .where.not(id: oc.id)
          .where("right(regexp_replace(customer_number, '\\D', '', 'g'), 10) = ?", phone)
          .exists?
    end
  end
end
