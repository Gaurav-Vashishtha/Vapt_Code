# frozen_string_literal: true

module ShopifyServices
  # Thin GraphQL wrapper for the abandoned pre-order OTP draft orders.
  # Every method returns a Result; nothing raises on Shopify userErrors.
  #
  #   svc = ShopifyServices::OtpDraftOrderService.for(shop)
  #   svc.create(input) / svc.update(gid, input) / svc.delete(gid) / svc.status(gid)
  #   svc.find_customer(phone_digits)
  class OtpDraftOrderService
    Result = Struct.new(:ok, :gid, :name, :status, :errors, keyword_init: true) do
      def ok? = ok
    end

    CREATE = <<~'GRAPHQL'
      mutation ($input: DraftOrderInput!) {
        draftOrderCreate(input: $input) {
          draftOrder { id name status }
          userErrors { field message }
        }
      }
    GRAPHQL

    UPDATE = <<~'GRAPHQL'
      mutation ($id: ID!, $input: DraftOrderInput!) {
        draftOrderUpdate(id: $id, input: $input) {
          draftOrder { id name status }
          userErrors { field message }
        }
      }
    GRAPHQL

    DELETE = <<~'GRAPHQL'
      mutation ($input: DraftOrderDeleteInput!) {
        draftOrderDelete(input: $input) {
          deletedId
          userErrors { field message }
        }
      }
    GRAPHQL

    STATUS = <<~'GRAPHQL'
      query ($id: ID!) {
        draftOrder(id: $id) { id name status }
      }
    GRAPHQL

    CUSTOMER = <<~'GRAPHQL'
      query ($query: String!) {
        customers(first: 1, query: $query) {
          edges { node { id firstName lastName email } }
        }
      }
    GRAPHQL

    def self.for(shop)
      shop.init_session
      new(ShopifyAPI::GraphQL.client)
    end

    def initialize(client)
      @client = client
    end

    def create(input)
      resp = run(CREATE, input: input)
      mutation_result(resp&.data&.draft_order_create, resp)
    end

    def update(gid, input)
      resp = run(UPDATE, id: gid, input: input)
      mutation_result(resp&.data&.draft_order_update, resp)
    end

    def delete(gid)
      resp = run(DELETE, input: { id: gid })
      data = resp&.data&.draft_order_delete
      errors = user_errors(data) + query_errors(resp)
      Result.new(ok: data&.deleted_id.present? && errors.empty?, gid: gid, errors: errors)
    end

    # status is "OPEN", "INVOICE_SENT", "COMPLETED", or nil when the draft no longer exists.
    def status(gid)
      resp = run(STATUS, id: gid)
      draft = resp&.data&.draft_order
      Result.new(ok: query_errors(resp).empty?, gid: draft&.id, name: draft&.name, status: draft&.status,
                 errors: query_errors(resp))
    end

    # Shopify customer for this phone (digits incl. country code), or nil.
    def find_customer(phone_digits)
      return nil if phone_digits.blank?

      terms = ["phone:+#{phone_digits}"]
      terms << "phone:#{phone_digits.last(10)}" if phone_digits.length > 10
      terms.each do |term|
        node = run(CUSTOMER, query: term)&.data&.customers&.edges&.first&.node
        return node if node.present?
      end
      nil
    end

    private

    def run(document, variables)
      @parsed ||= {}
      @parsed[document] ||= @client.parse(document)
      @client.query(@parsed[document], variables: variables)
    end

    def mutation_result(data, resp)
      draft = data&.draft_order
      errors = user_errors(data) + query_errors(resp)
      Result.new(ok: draft.present? && errors.empty?, gid: draft&.id, name: draft&.name, status: draft&.status,
                 errors: errors)
    end

    def user_errors(data)
      Array(data&.user_errors).map { |e| { field: Array(e.field).join("."), message: e.message } }
    end

    def query_errors(resp)
      Array(resp&.errors&.messages&.values).flatten.map { |m| { field: nil, message: m.to_s } }
    rescue StandardError
      []
    end
  end
end
