module ShopifyServices
  class CustomerPullService < ShopifyServices::GraphqlService
    attr_reader :shop, :client, :since

    # ShopifyServices::CustomerPullService.call(shop)
    # ShopifyServices::CustomerPullService.call(shop, { since: 1.day.ago })  # incremental: only customers updated after since
    def initialize(client, shop, options = {})
      @client = client
      @shop = shop
      @since = options.is_a?(Hash) ? (options[:since] || options["since"]) : nil
    end

    def get_and_store_customer
      after = ""
      has_next_page = true
      query_filter = build_customer_query_filter

      while has_next_page
        query_str = ""
        variables = { "first" => 10 }

        if after.present?
          variables["after"] = after
        end

        if query_filter.present?
          variables["query"] = query_filter
        end

        if after.blank? && query_filter.blank?
          query_str = <<~GRAPHQL
            query ($first: Int!) {
              customers(first: $first) {
                pageInfo { hasPreviousPage hasNextPage startCursor endCursor }
                edges { node { id firstName lastName phone email locale state lifetimeDuration verifiedEmail amountSpent { amount currencyCode } tags statistics { predictedSpendTier } defaultAddress { countryCodeV2 } addresses { id address1 address2 city company coordinatesValidated country countryCodeV2 firstName formatted formattedArea latitude longitude name lastName phone provinceCode province validationResultSummary zip } numberOfOrders lastOrder { id } } }
              }
            }
          GRAPHQL
        elsif after.blank? && query_filter.present?
          query_str = <<~GRAPHQL
            query ($first: Int!, $query: String!) {
              customers(first: $first, query: $query) {
                pageInfo { hasPreviousPage hasNextPage startCursor endCursor }
                edges { node { id firstName lastName phone email locale state lifetimeDuration verifiedEmail amountSpent { amount currencyCode } tags statistics { predictedSpendTier } defaultAddress { countryCodeV2 } addresses { id address1 address2 city company coordinatesValidated country countryCodeV2 firstName formatted formattedArea latitude longitude name lastName phone provinceCode province validationResultSummary zip } numberOfOrders lastOrder { id } } }
              }
            }
          GRAPHQL
        elsif after.present? && query_filter.blank?
          query_str = <<~GRAPHQL
            query ($first: Int!, $after: String!) {
              customers(first: $first, after: $after) {
                pageInfo { hasPreviousPage hasNextPage startCursor endCursor }
                edges { node { id firstName lastName phone email locale state lifetimeDuration verifiedEmail amountSpent { amount currencyCode } tags statistics { predictedSpendTier } defaultAddress { countryCodeV2 } addresses { id address1 address2 city company coordinatesValidated country countryCodeV2 firstName formatted formattedArea latitude longitude name lastName phone provinceCode province validationResultSummary zip } numberOfOrders lastOrder { id } } }
              }
            }
          GRAPHQL
        else
          query_str = <<~GRAPHQL
            query ($first: Int!, $after: String!, $query: String!) {
              customers(first: $first, after: $after, query: $query) {
                pageInfo { hasPreviousPage hasNextPage startCursor endCursor }
                edges { node { id firstName lastName phone email locale state lifetimeDuration verifiedEmail amountSpent { amount currencyCode } tags statistics { predictedSpendTier } defaultAddress { countryCodeV2 } addresses { id address1 address2 city company coordinatesValidated country countryCodeV2 firstName formatted formattedArea latitude longitude name lastName phone provinceCode province validationResultSummary zip } numberOfOrders lastOrder { id } } }
              }
            }
          GRAPHQL
        end

        query = @client.parse(query_str)
        resp = @client.query(query, variables: variables)

        if resp.blank? || resp.data.blank?
          # SlackNotifier::CLIENT.ping(text: "CustomerPullJob Error (#{Rails.env}) - #{resp.inspect}")
          break
        end

        has_next_page = resp.data.customers.page_info.has_next_page
        after = resp.data.customers.page_info.end_cursor
        ShopifyServices::CustomerDataSaveService.call(@shop, resp)
      end

      @shop.update(initial_customer_pull_completed: Time.current)
      Rails.logger.info "Shop completed: #{@shop.shopify_domain}"
    end

    def call
      get_and_store_customer
    end

    private

    # Only customers updated (or created) after since. When since is nil, pull all.
    def build_customer_query_filter
      return nil if @since.blank?

      # Shopify search: updated_at accepts date or datetime (e.g. updated_at:>=2019-12-01)
      ts = @since.respond_to?(:utc) ? @since.utc : Time.zone.parse(@since.to_s).utc
      "updated_at:>=#{ts.strftime('%Y-%m-%d')}"
    end
  end
end
