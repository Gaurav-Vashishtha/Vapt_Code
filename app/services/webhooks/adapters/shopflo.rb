# frozen_string_literal: true

module Webhooks
  module Adapters
    # Shopflo payload quirks this absorbs, all confirmed against their samples:
    # abandoned_checkout_url is empty on checkout_abandoned; customer.email is
    # null while top-level email is populated; cart_variant_ids/cart_product_ids
    # disagree with line_items (line_items wins); no merchant identifier on any
    # funnel event, which is why the shop comes from the endpoint token.
    class Shopflo < Base
      SHOPFLO_CHECKOUT_BASE = 'https://checkout.shopflo.co/?tokenId='

      def call
        case event_name
        when 'checkout_abandoned'  then normalize_checkout_abandoned
        when 'added_to_cart_ui'    then normalize_added_to_cart
        when 'product_page_viewed' then normalize_product_viewed
        when 'checkout_clicked'    then normalize_checkout_clicked
        when 'order_completed'     then normalize_order_completed
        else Normalized.new(role: :ignore, payload: {}, external_references: [])
        end
      end

      def self.dedup_key_for(event_name, payload)
        body = payload.is_a?(Hash) ? payload.deep_stringify_keys : {}
        primary = [
          body['checkout_id'], body['cart_token'], body['order_id'],
          body['token_id'].is_a?(String) ? body['token_id'] : nil,
          body['session_id'], body['sessionId']
        ].find { |v| v.to_s.strip.present? }
        stamp = body['timestamp'] || body['updated_at'] || body['created_at']

        return nil if primary.blank?

        "#{event_name}:#{primary}:#{stamp}"
      end

      private

      def normalize_checkout_abandoned
        customer = payload['customer'] || {}
        shipping = payload['shipping_address'] || {}
        billing  = payload['billing_address'] || {}

        checkout_id = first_present(payload['checkout_id'], payload['cart_token'], payload['session_id'])
        return Normalized.new(role: :ignore, payload: {}, external_references: []) if checkout_id.blank?

        external_id = "flo_#{checkout_id}"
        phone = first_present(customer['phone'], payload['phone'], shipping['phone'], billing['phone'])
        country = derive_country_code(phone, shipping, billing)
        recovery_url = recovery_url_for(checkout_id)
        items = line_items_from(payload['line_items'])
        total = scaled(payload['total_price'] || payload['subtotal_price'])
        occurred_at = parse_time(payload['created_at']) || parse_time(payload['timestamp']) || Time.current

        Normalized.new(
          role: :trigger,
          event_type_key: 'abandoned_cart',
          source_external_id: external_id,
          dedup_key: self.class.dedup_key_for(event_name, payload),
          occurred_at: occurred_at,
          phone: phone,
          country_code: country,
          email: first_present(payload['email'], customer['email']),
          first_name: first_present(customer['first_name']) || 'Customer',
          marketing_consent: customer['marketing_consent'],
          recovery_url: recovery_url,
          total_price: total,
          currency: payload['currency'].to_s.presence || 'INR',
          featured_image: featured_image_from(items),
          external_references: [external_id, checkout_id, payload['cart_token'].to_s].compact_blank.uniq,
          suppresses: [],
          marks_recovered: false,
          # Root key must stay `checkout`: EventRegistry's abandoned_cart
          # variable paths and DispatchEventJob::RECIPIENT_PATHS both read
          # checkout.* and are shared with the Shopify-poll funnel.
          payload: {
            'checkout' => {
              'id'                     => external_id,
              'token'                  => external_id,
              'abandoned_checkout_url' => recovery_url.to_s,
              'created_at'             => occurred_at.to_s,
              'total_price'            => format_amount(total),
              'currency'               => payload['currency'].to_s,
              'line_items'             => items,
              'line_items_count'       => items.sum { |i| i['quantity'].to_i }.to_s,
              'phone'                  => phone.to_s,
              'source'                 => 'shopflo',
              'customer' => {
                'first_name'        => first_present(customer['first_name']).to_s,
                'last_name'         => first_present(customer['last_name']).to_s,
                'phone'             => phone.to_s,
                'email'             => first_present(payload['email'], customer['email']).to_s,
                'marketing_consent' => customer['marketing_consent']
              },
              'shipping_address' => address_payload(shipping, phone, country),
              'billing_address'  => address_payload(billing, phone, country)
            }
          }
        )
      end

      def normalize_added_to_cart
        user = payload['user_data'] || {}
        session_id = first_present(payload['session_id'], payload['long_session_id'])
        return Normalized.new(role: :ignore, payload: {}, external_references: []) if session_id.blank?

        external_id = "flo_cart_#{session_id}"
        phone = first_present(user['phone'], payload['phone'])
        country = derive_country_code(phone)
        items = line_items_from(payload['line_items'])
        total = scaled(payload['total_price'])
        cart_url = cart_permalink_for(payload['line_items'])
        occurred_at = parse_time(payload['timestamp']) || Time.current

        Normalized.new(
          role: :trigger,
          event_type_key: 'cart_abandoned',
          source_external_id: external_id,
          dedup_key: self.class.dedup_key_for(event_name, payload),
          occurred_at: occurred_at,
          phone: phone,
          country_code: country,
          email: first_present(user['email'], payload['email']),
          first_name: first_present(user['firstName'], user['first_name']) || 'Customer',
          marketing_consent: nil,
          recovery_url: cart_url,
          total_price: total,
          currency: payload['currency'].to_s.presence || 'INR',
          featured_image: featured_image_from(items),
          external_references: [external_id, session_id].compact_blank.uniq,
          suppresses: [],
          marks_recovered: false,
          payload: {
            'cart' => {
              'id'               => external_id,
              'token'            => external_id,
              'cart_url'         => cart_url.to_s,
              'created_at'       => occurred_at.to_s,
              'total_price'      => format_amount(total),
              'currency'         => payload['currency'].to_s,
              'line_items'       => items,
              'line_items_count' => items.sum { |i| i['quantity'].to_i }.to_s,
              'phone'            => phone.to_s,
              'source'           => 'shopflo',
              'customer' => {
                'first_name' => first_present(user['firstName'], user['first_name']).to_s,
                'last_name'  => first_present(user['lastName'], user['last_name']).to_s,
                'phone'      => phone.to_s,
                'email'      => first_present(user['email']).to_s
              },
              'shipping_address' => { 'phone' => phone.to_s, 'country_code' => country.to_s }
            }
          }
        )
      end

      def normalize_product_viewed
        data = payload['data'] || {}
        user = data['user_data'] || {}
        session_id = first_present(payload['session_id'], data['long_session_id'])
        product_url = first_present(data['product_url'])
        return Normalized.new(role: :ignore, payload: {}, external_references: []) if session_id.blank? || product_url.blank?

        # Keyed per (session, product) rather than per view, or a buyer who
        # refreshes the page three times gets three messages.
        external_id = "flo_browse_#{session_id}_#{Digest::SHA256.hexdigest(product_url)[0, 12]}"
        phone = first_present(user['phone'], payload['phone'])
        country = derive_country_code(phone)
        price = scaled(data['product_price'])
        occurred_at = parse_time(payload['timestamp']) || Time.current

        Normalized.new(
          role: :trigger,
          event_type_key: 'browse_abandoned',
          source_external_id: external_id,
          dedup_key: self.class.dedup_key_for(event_name, payload),
          occurred_at: occurred_at,
          phone: phone,
          country_code: country,
          email: first_present(user['email'], data['email']),
          first_name: first_present(user['firstName'], user['first_name']) || 'Customer',
          marketing_consent: nil,
          recovery_url: product_url,
          total_price: price,
          currency: 'INR',
          featured_image: first_present(data['product_image']),
          external_references: [external_id, session_id].compact_blank.uniq,
          suppresses: [],
          marks_recovered: false,
          payload: {
            'browse' => {
              'id'            => external_id,
              'token'         => external_id,
              'product_name'  => first_present(data['product_name']).to_s,
              'product_url'   => product_url.to_s,
              'product_image' => first_present(data['product_image']).to_s,
              'product_price' => format_amount(price),
              'created_at'    => occurred_at.to_s,
              'phone'         => phone.to_s,
              'source'        => 'shopflo',
              'customer' => {
                'first_name' => first_present(user['firstName'], user['first_name']).to_s,
                'phone'      => phone.to_s,
                'email'      => first_present(user['email']).to_s
              },
              'shipping_address' => { 'phone' => phone.to_s, 'country_code' => country.to_s }
            }
          }
        )
      end

      def normalize_checkout_clicked
        user = payload['user_data'] || {}
        refs = [
          payload['checkout_id'], payload['token_id'], payload['session_id'],
          payload['checkout_id'].present? ? "flo_#{payload['checkout_id']}" : nil,
          payload['session_id'].present? ? "flo_cart_#{payload['session_id']}" : nil
        ].compact_blank.map(&:to_s).uniq

        Normalized.new(
          role: :suppress,
          suppresses: Array(definition[:suppresses]),
          marks_recovered: false,
          source_external_id: refs.first,
          dedup_key: self.class.dedup_key_for(event_name, payload),
          occurred_at: parse_time(payload['timestamp']) || Time.current,
          phone: first_present(user['phone'], payload['phone']),
          external_references: refs,
          payload: {}
        )
      end

      def normalize_order_completed
        customer = payload['customer'] || {}
        shipping = payload['shipping_address'] || {}
        refs = [
          payload['checkout_id'], payload['cart_token'], payload['token_id'], payload['session_id'],
          payload['checkout_id'].present? ? "flo_#{payload['checkout_id']}" : nil,
          payload['cart_token'].present? ? "flo_#{payload['cart_token']}" : nil,
          payload['session_id'].present? ? "flo_cart_#{payload['session_id']}" : nil
        ].compact_blank.map(&:to_s).uniq

        Normalized.new(
          role: :suppress,
          suppresses: Array(definition[:suppresses]),
          marks_recovered: true,
          source_external_id: refs.first,
          dedup_key: self.class.dedup_key_for(event_name, payload),
          occurred_at: parse_time(payload['created_at']) || parse_time(payload['timestamp']) || Time.current,
          phone: first_present(customer['phone'], payload['phone'], shipping['phone']),
          email: first_present(payload['email'], customer['email']),
          total_price: scaled(payload['total_price']),
          currency: payload['currency'].to_s.presence || 'INR',
          external_references: refs,
          payload: {}
        )
      end

      # A blank recovery URL drops the template's URL-button parameter, which
      # Meta rejects with 131008.
      def recovery_url_for(checkout_id)
        from_notes = Array(payload['note_attributes'])
                       .find { |attr| attr.is_a?(Hash) && attr['name'].to_s == 'shopflo_checkout_url' }
                       &.dig('value').to_s.strip

        from_utm = payload.dig('utm_params', 'shopflo_checkout_url').to_s.strip

        # token_id is a full URL on checkout_abandoned and a bare UUID on every
        # other event, so only take it when it looks like a link.
        token_id = payload['token_id']
        from_token = token_id.is_a?(String) && token_id.start_with?('http') ? token_id.strip : ''

        declared = payload['abandoned_checkout_url'].to_s.strip

        first_present(declared, from_notes, from_utm, from_token) ||
          "#{SHOPFLO_CHECKOUT_BASE}#{checkout_id}"
      end

      def line_items_from(raw)
        Array(raw).filter_map do |item|
          next unless item.is_a?(Hash)

          {
            'title'      => first_present(item['title'], item['name']).to_s,
            'quantity'   => [item['quantity'].to_i, 1].max,
            'price'      => format_amount(scaled(item['price'])),
            'variant_id' => first_present(item['variant_id'], item['id'], item['item_id']).to_s,
            'product_id' => item['product_id'].to_s,
            'image'      => first_present(item['product_image'], item['image']).to_s
          }
        end
      end

      def featured_image_from(items)
        first_present(payload['image_url'], items.map { |i| i['image'] }.find(&:present?))
      end

      # Matches buildShopifyPermalink in CodKingAbandonedCarts.jsx so the link
      # a buyer taps resolves to the cart the merchant sees in the admin.
      def cart_permalink_for(raw_items)
        return nil if shop&.shopify_domain.blank?

        pairs = Array(raw_items).filter_map do |item|
          next unless item.is_a?(Hash)

          variant_id = first_present(item['variant_id'], item['item_id'], item['id'])
          next if variant_id.blank?

          "#{variant_id}:#{[item['quantity'].to_i, 1].max}"
        end
        return nil if pairs.empty?

        "https://#{shop.shopify_domain}/cart/#{pairs.join(',')}?storefront=true"
      end

      def address_payload(address, fallback_phone, country)
        {
          'address1'     => address['address1'].to_s,
          'city'         => address['city'].to_s,
          'province'     => address['province'].to_s,
          'zip'          => address['zip'].to_s,
          'country'      => address['country'].to_s,
          'phone'        => first_present(address['phone'], fallback_phone).to_s,
          'country_code' => first_present(address['country_code'], country).to_s
        }
      end

      def format_amount(amount)
        return '' if amount.nil?

        format('%.2f', amount.to_f)
      end
    end
  end
end
