module ShopifyServices
  class OrderDetailsGetService < ShopifyServices::GraphqlService
    def initialize(client, shop, order_id, data_query = OrderQueries::SingleOrderDetails)
      @client = client
      @shop = shop
      @order_id = order_id
      @data_query = data_query
    end

    def call
      resp = @client.query(@data_query, variables: { id: "gid://shopify/Order/#{@order_id}" })
      order = resp&.data&.order
      return nil if order.blank?

      {
        line_items: order.line_items.edges.map { |edge| line_item_payload(edge.node) },
        subtotal: money(order.subtotal_price_set),
        shipping: money(order.total_shipping_price_set),
        discount: money(order.total_discounts_set),
        tax: money(order.total_tax_set),
        total: money(order.total_price_set),
        shipping_address: address_payload(order.shipping_address),
      }
    end

    private

    def line_item_payload(item)
      {
        title: item.title,
        variant_title: item.variant_title,
        quantity: item.quantity,
        original_unit_price: money(item.original_unit_price_set),
        discounted_unit_price: money(item.discounted_unit_price_set),
        image_url: item.image&.url,
      }
    end

    def money(price_set)
      price_set&.shop_money&.amount
    end

    def address_payload(address)
      return nil if address.blank?

      {
        name: address.name,
        lines: [
          address.address1,
          address.address2,
          [address.city, address.province, address.zip].compact_blank.join(', '),
          address.country,
        ].compact_blank,
      }
    end
  end
end
