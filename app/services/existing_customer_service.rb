# frozen_string_literal: true

# Has this shopper ordered from this shop before, and when was the last order?
#
# Feeds two payment-rule settings: the repeat-customer discount on prepaid
# rules and the COD cooling period.
#   1. Our customers table (by phone; no ParcelX call) supplies the email we
#      hold for this person when the shopper hasn't given one.
#   2. Shopify is searched by phone, then email, for the store's customer
#      record: numberOfOrders and lastOrder decide the answer.
# Any failure reads as "not existing" so a lookup problem never blocks checkout.
class ExistingCustomerService
  def self.call(shop, phone:, email: nil)
    new(shop, phone: phone, email: email).call
  end

  # phone is the full number with its country code, as the popup sends it
  # ("917003393597" or "+917003393597").
  def initialize(shop, phone:, email: nil)
    @shop = shop
    @phone = phone.to_s
    @email = Customer.real_email(email)
  end

  def call
    email = @email || known_customer&.then { |c| Customer.real_email(c.email) }
    return not_existing if phone_digits.blank? && email.blank?

    from_shopify(email)
  rescue StandardError => e
    Rails.logger.error "ExistingCustomerService failed shop=#{@shop&.id}: #{e.message}"
    not_existing
  end

  private

  # Customer.phone is stored as "+<country code><number>".
  def known_customer
    return nil if full_phone.blank?

    Customer.where(phone: full_phone)
            .order(Arel.sql("email IS NULL"), updated_at: :desc)
            .first
  end

  def full_phone
    phone_digits.length > 10 ? "+#{phone_digits}" : nil
  end

  def from_shopify(email)
    @shop.init_session
    client = ShopifyAPI::GraphQL.client
    query = client.parse <<~GRAPHQL
      query ($query: String!) {
        customers(first: 1, query: $query) {
          edges { node { numberOfOrders lastOrder { createdAt } } }
        }
      }
    GRAPHQL

    shopify_search_terms(email).each do |term|
      resp = client.query(query, variables: { "query" => term })
      node = resp&.data&.customers&.edges&.first&.node
      next if node.blank?

      orders = node.number_of_orders.to_i
      next if orders.zero?

      return build(orders, node.last_order&.created_at)
    end
    not_existing
  end

  def shopify_search_terms(email)
    terms = []
    terms << "phone:#{full_phone}" if full_phone
    terms << "phone:#{phone_digits.last(10)}" if phone_digits.length >= 10
    terms << %(email:"#{email.delete('"')}") if email.present?
    terms.uniq
  end

  def phone_digits
    @phone_digits ||= @phone.gsub(/\D/, "")
  end

  def build(orders_count, last_order_date)
    {
      existing: true,
      orders_count: orders_count,
      last_order_date: last_order_date.respond_to?(:iso8601) ? last_order_date.iso8601 : last_order_date
    }
  end

  def not_existing
    { existing: false, orders_count: 0, last_order_date: nil }
  end
end
