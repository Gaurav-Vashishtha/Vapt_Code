# frozen_string_literal: true

module ShopifyServices
  # Admin REST Abandoned Checkout endpoints return 404 on current API versions (Checkout API deprecation).
  # Use Admin GraphQL `abandonedCheckouts` / `node` instead.
  #
  # Console (activate session first):
  #   shop = Shop.find_by(shopify_domain: "example.myshopify.com")
  #   shop.init_session
  #   ShopifyServices::AbandonedCheckoutGraphqlFetcher.find(shop, 40359868170538)
  class AbandonedCheckoutGraphqlFetcher
    PAGE_SIZE = 50
    LINE_ITEMS_PAGE = 100

    CheckoutWrapper = Struct.new(
      :id,
      :abandoned_checkout_url,
      :created_at,
      :total_price,
      :phone,
      :note,
      :line_items,
      :customer,
      :shipping_address,
      :billing_address,
      :note_attributes,
      keyword_init: true
    )

    LineItemWrapper = Struct.new(
      :title,
      :presentment_title,
      :quantity,
      :variant_id,
      :product_id,
      :properties,
      keyword_init: true
    )

    class << self
      def find(shop, checkout_id)
        gid = abandoned_checkout_gid(checkout_id)
        shop.with_shopify_session do
          client = ShopifyAPI::GraphQL.client
          query = client.parse(<<~GRAPHQL)
            query($id: ID!) {
              node(id: $id) {
                ... on AbandonedCheckout {
                  #{checkout_fields_fragment}
                }
              }
            }
          GRAPHQL
          response = client.query(query, variables: { id: gid })
          log_graphql_errors("AbandonedCheckoutGraphqlFetcher.find", response)
          node = response&.data&.node
          return nil if node.blank?

          build_checkout_wrapper(node)
        end
      end

      # +min_created+ should be a Time/DateTime (typically beginning of local day).
      def fetch_created_since(shop, min_created)
        min_created = min_created.in_time_zone if min_created.respond_to?(:in_time_zone)
        filter = "created_at:>=#{min_created.utc.iso8601}"
        results = []
        cursor = nil

        shop.with_shopify_session do
          client = ShopifyAPI::GraphQL.client
          query = client.parse(<<~GRAPHQL)
            query($first: Int!, $after: String, $query: String) {
              abandonedCheckouts(first: $first, after: $after, query: $query, sortKey: CREATED_AT, reverse: false) {
                pageInfo {
                  hasNextPage
                  endCursor
                }
                edges {
                  cursor
                  node {
                    #{checkout_fields_fragment}
                  }
                }
              }
            }
          GRAPHQL

          loop do
            response = client.query(
              query,
              variables: { first: PAGE_SIZE, after: cursor, query: filter }
            )
            log_graphql_errors("AbandonedCheckoutGraphqlFetcher.fetch_created_since", response)
            connection = response&.data&.abandoned_checkouts
            break if connection.blank?

            connection.edges.each do |edge|
              results << build_checkout_wrapper(edge.node) if edge&.node
            end

            page_info = connection.page_info
            break unless page_info&.has_next_page

            cursor = page_info.end_cursor
            break if cursor.blank?
          end
        end

        results
      end

      private

      def abandoned_checkout_gid(checkout_id)
        s = checkout_id.to_s.strip
        return s if s.start_with?("gid://shopify/AbandonedCheckout/")

        "gid://shopify/AbandonedCheckout/#{s}"
      end

      def checkout_fields_fragment
        @checkout_fields_fragment ||= <<~GRAPHQL.squish
          id
          abandonedCheckoutUrl
          createdAt
          note
          customAttributes { key value }
          totalPriceSet { shopMoney { amount } }
          customer {
            firstName
            defaultPhoneNumber { phoneNumber }
          }
          shippingAddress { phone countryCode countryCodeV2 }
          billingAddress { phone countryCode countryCodeV2 }
          lineItems(first: #{LINE_ITEMS_PAGE}) {
            edges {
              node {
                title
                variantTitle
                quantity
                customAttributes { key value }
                variant { legacyResourceId }
                product { legacyResourceId }
              }
            }
          }
        GRAPHQL
      end

      def build_checkout_wrapper(node)
        return nil unless node.respond_to?(:line_items) && node.respond_to?(:abandoned_checkout_url)

        legacy_id = node.id.to_s.split("/").last.to_i
        amount = node.total_price_set&.shop_money&.amount
        total_price = amount.present? ? amount.to_f : 0.0

        line_items = (node.line_items&.edges || []).filter_map do |edge|
          li = edge&.node
          next if li.blank?

          title = li.title.to_s
          vtitle = li.variant_title.to_s.strip
          presentment =
            if vtitle.present? && title.present? && !title.include?(vtitle)
              "#{title} / #{vtitle}"
            else
              title.presence || vtitle
            end

          props = (li.custom_attributes || []).map do |a|
            Struct.new(:name, :value).new(a.key.to_s, a.value.to_s)
          end

          LineItemWrapper.new(
            title: title,
            presentment_title: presentment,
            quantity: li.quantity,
            variant_id: li.variant&.legacy_resource_id,
            product_id: li.product&.legacy_resource_id,
            properties: props
          )
        end

        note_attrs = (node.custom_attributes || []).map do |a|
          Struct.new(:name, :value).new(a.key.to_s, a.value.to_s)
        end

        shipping = wrap_mailing_address(node.shipping_address)
        billing = wrap_mailing_address(node.billing_address)
        customer = wrap_customer(node.customer)

        phone =
          shipping&.phone.presence ||
          billing&.phone.presence ||
          customer_phone_from_graphql(node.customer)

        CheckoutWrapper.new(
          id: legacy_id,
          abandoned_checkout_url: node.abandoned_checkout_url.to_s,
          created_at: node.created_at.to_s,
          total_price: total_price,
          phone: phone,
          note: node.note.to_s,
          line_items: line_items,
          customer: customer,
          shipping_address: shipping,
          billing_address: billing,
          note_attributes: note_attrs
        )
      end

      def wrap_mailing_address(addr)
        return nil if addr.blank?

        cc =
          if addr.respond_to?(:country_code_v2) && addr.country_code_v2.present?
            addr.country_code_v2.to_s
          elsif addr.respond_to?(:country_code) && addr.country_code.present?
            addr.country_code.to_s
          end

        Struct.new(:phone, :country_code).new(addr.phone, cc)
      end

      # Must expose `phone` as well as `first_name`: the BSP abandoned-cart
      # scheduler's payload builder reads `checkout.customer&.phone`, and a
      # phone-less struct raises NoMethodError there — which the per-cart
      # rescue swallows, silently dropping every Shopify checkout that has a
      # customer attached (leaving only the pre-order OTP funnel working).
      def wrap_customer(c)
        return nil if c.blank?

        Struct.new(:first_name, :phone).new(
          c.first_name.to_s.presence,
          customer_phone_from_graphql(c)
        )
      end

      def customer_phone_from_graphql(c)
        c&.default_phone_number&.phone_number.to_s.presence
      end

      def log_graphql_errors(context, response)
        errs = response&.errors&.inspect
        return if errs.blank? || errs == "[]"

        Rails.logger.warn("#{context} GraphQL errors: #{errs}")
      end
    end
  end
end
