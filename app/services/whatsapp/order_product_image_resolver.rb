module Whatsapp
  # Picks a product image URL out of an event payload for templates whose
  # header_media is configured as a dynamic `order_product_image` source. The
  # caller is responsible for passing the right payload (DispatchEventJob
  # already shape-checks it).
  #
  # Resolution order, per first line item with content:
  #   1. Any image URL the webhook payload itself carries (rare — only
  #      checkout/storefront payloads tend to). Saves an API call when present.
  #   2. Shopify REST lookup by product_id → first product image URL.
  #
  # Shopify order webhooks do NOT embed line-item images, so the API fallback
  # is the load-bearing path for the order events. We cache the result per
  # (shop, product) for an hour to avoid hammering the products API when the
  # same product ships in many orders.
  class OrderProductImageResolver
    # Event keys handled here. abandoned_cart uses `checkout.*`, the rest use
    # `order.*`. Everything else (campaign_broadcast, future events) returns nil.
    ORDER_EVENTS = %w[order_created order_fulfilled first_time_purchase cod_verification
                      cod_verification_reminder order_cancelled order_out_for_delivery order_delivered feedback_request reorder_reminder].freeze

    # Per-(shop, product) image cache TTL. Products change images rarely; 1h
    # gives us plenty of dedup on hot products without serving stale images
    # for too long.
    CACHE_TTL = 1.hour

    # Meta media headers render only JPEG/PNG directly. HEIC/HEIF (iPhone
    # uploads) and WebP are rejected at send time, but we can transcode them to
    # JPEG before upload (see Whatsapp::ImageTranscoder), so they still count as
    # deliverable. SVG/GIF stay unsupported — rasterising an SVG picks the wrong
    # size and GIFs are usually animated.
    SUPPORTED_IMAGE_EXTENSIONS = %w[.jpg .jpeg .png].freeze
    CONVERTIBLE_IMAGE_EXTENSIONS = %w[.heic .heif .webp].freeze

    def self.supported_image_url?(url)
      matches_extension?(url, SUPPORTED_IMAGE_EXTENSIONS)
    end

    def self.convertible_image_url?(url)
      matches_extension?(url, CONVERTIBLE_IMAGE_EXTENSIONS)
    end

    def self.deliverable_image_url?(url)
      supported_image_url?(url) || convertible_image_url?(url)
    end

    def self.matches_extension?(url, extensions)
      return false unless url.is_a?(String) && url.start_with?('http')

      path = url.split('?').first.to_s.downcase
      extensions.any? { |ext| path.end_with?(ext) }
    end

    def self.call(payload:, event_type_key:, shop: nil)
      return nil unless payload.is_a?(Hash)

      line_items =
        if ORDER_EVENTS.include?(event_type_key.to_s)
          safe_dig(payload, 'order', 'line_items')
        elsif event_type_key.to_s == 'abandoned_cart'
          safe_dig(payload, 'checkout', 'line_items')
        end

      Array(line_items).each do |li|
        # Cheap path — payload already includes an image URL.
        url = url_from_line_item(li)
        return url if url.present?

        # Fallback — look the product up via Shopify REST, preferring the
        # image attached to the ordered VARIANT over the product's featured one.
        next unless shop
        product_id = li.is_a?(Hash) ? (li['product_id'] || li[:product_id]) : nil
        next if product_id.blank?
        variant_id = li.is_a?(Hash) ? (li['variant_id'] || li[:variant_id]) : nil

        api_url = lookup_product_image(shop: shop, product_id: product_id, variant_id: variant_id)
        return api_url if api_url.present?
      end

      nil
    end

    # Common paths Shopify payloads use for a line item's image. Order
    # webhooks don't carry these, but checkout/storefront payloads sometimes
    # do — try them first to skip the API hit when possible.
    # Hash#dig raises TypeError when an intermediate is present but not
    # dig-able, and webhook-sourced payloads sometimes carry `image` /
    # `featured_image` as a plain URL string — so every path is walked with
    # safe_dig, and a bare string at an intermediate key counts as the URL.
    def self.url_from_line_item(line_item)
      return nil unless line_item.is_a?(Hash)

      # Variant-level images first: a line item's `image` / `featured_image`
      # on storefront payloads is usually the variant's, but `product.image`
      # is the product's featured image and must come last so a multi-variant
      # product doesn't show a sibling variant's picture.
      candidates = [
        safe_dig(line_item, 'variant', 'image', 'src'),
        safe_dig(line_item, 'variant', 'image', 'url'),
        safe_dig(line_item, 'variant', 'featured_image', 'src'),
        safe_dig(line_item, 'variant', 'featured_image', 'url'),
        safe_dig(line_item, 'image', 'src'),
        safe_dig(line_item, 'image', 'url'),
        string_or_nil(line_item['image']),
        string_or_nil(line_item['image_url']),
        safe_dig(line_item, 'featured_image', 'src'),
        safe_dig(line_item, 'featured_image', 'url'),
        string_or_nil(line_item['featured_image']),
        safe_dig(line_item, 'product', 'image', 'src'),
      ]

      url = candidates.find { |u| supported_image_url?(u) } ||
            candidates.find { |u| convertible_image_url?(u) }
      url&.strip
    end

    def self.safe_dig(obj, *keys)
      keys.reduce(obj) { |acc, key| acc.is_a?(Hash) ? acc[key] : nil }
    end

    def self.string_or_nil(value)
      value.is_a?(String) ? value : nil
    end

    # Fetch the image for an ordered variant via Shopify REST. The variant's
    # own `image_id` wins (so a blue shirt shows the blue photo); only when the
    # variant has no dedicated image do we fall back to the product's first
    # deliverable image. Cached per shop+product+variant so the same popular
    # SKU shipping in many orders doesn't repeatedly hit the products endpoint.
    # Returns nil on any API failure (caller falls back to the template's
    # static example_url).
    def self.lookup_product_image(shop:, product_id:, variant_id: nil)
      cache_key = "whatsapp/product_image/#{shop.id}/#{product_id}/#{variant_id.presence || 'product'}"

      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        shop.init_session
        product = ::ShopifyAPI::Product.find(product_id, params: { fields: 'id,images,variants' })
        images = Array(product&.images)

        variant_image_id = nil
        if variant_id.present?
          variant = Array(product&.variants).find { |v| attr_of(v, 'id').to_s == variant_id.to_s }
          variant_image_id = attr_of(variant, 'image_id') if variant
        end

        ordered =
          if variant_image_id.present?
            matched = images.select { |img| attr_of(img, 'id').to_s == variant_image_id.to_s }
            matched + (images - matched)
          else
            images
          end

        srcs = ordered.map { |img| attr_of(img, 'src') }
        src = srcs.find { |s| supported_image_url?(s) } || srcs.find { |s| convertible_image_url?(s) }
        src.is_a?(String) ? src.strip : nil
      end
    rescue => e
      Rails.logger.warn("[order_product_image] shop=#{shop&.id} product=#{product_id} variant=#{variant_id} lookup failed: #{e.class}: #{e.message}")
      nil
    end

    def self.attr_of(obj, key)
      return nil if obj.nil?
      return obj[key] || obj[key.to_sym] if obj.is_a?(Hash)

      obj.respond_to?(key) ? obj.public_send(key) : nil
    end
  end
end
