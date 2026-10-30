# frozen_string_literal: true

module CodForm
  # ORD-6: match the buyer to a Shopify customer by phone, then by email, else create one.
  # Never writes a placeholder email. Every failure is swallowed (returns nil): Shopify then
  # matches the draft order's email / phone itself.
  class CustomerResolver
    FIND_QUERY = <<~GRAPHQL
      query ($query: String!) {
        customers(first: 1, query: $query) {
          edges { node { id } }
        }
      }
    GRAPHQL

    CREATE_MUTATION = <<~GRAPHQL
      mutation ($input: CustomerInput!) {
        customerCreate(input: $input) {
          customer { id }
          userErrors { field message }
        }
      }
    GRAPHQL

    class << self
      # => "gid://shopify/Customer/…" or nil
      def call(shop, phone_e164:, email: nil, first_name: nil, last_name: nil)
        phone = phone_e164.to_s.gsub(/\s+/, "")
        email = email.to_s.strip.downcase
        return nil if phone.empty? && email.empty?

        find(shop, %(phone:#{escape(phone)})) ||
          (email.empty? ? nil : find(shop, %(email:"#{escape(email)}"))) ||
          create(shop, phone: phone, email: email, first_name: first_name, last_name: last_name)
      rescue StandardError => e
        Rails.logger.warn("[CodForm::CustomerResolver] shop_id=#{shop.id} #{e.class}")
        nil
      end

      private

      def find(shop, term)
        return nil if term.end_with?(":")

        data, _errors = CodForm::CatalogService.admin_query(shop, FIND_QUERY, { "query" => term })
        Array(data.dig("customers", "edges")).first&.dig("node", "id").presence
      end

      def create(shop, phone:, email:, first_name:, last_name:)
        input = {}
        input["phone"] = phone unless phone.empty?
        input["email"] = email unless email.empty?
        input["firstName"] = first_name.to_s.strip unless first_name.to_s.strip.empty?
        input["lastName"] = last_name.to_s.strip unless last_name.to_s.strip.empty?

        data, _errors = CodForm::CatalogService.admin_query(shop, CREATE_MUTATION, { "input" => input })
        data.dig("customerCreate", "customer", "id").presence
      end

      def escape(value)
        value.to_s.gsub("\\", "\\\\\\\\").gsub('"', '\\"')
      end
    end
  end
end
