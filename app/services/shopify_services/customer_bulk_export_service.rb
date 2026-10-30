# frozen_string_literal: true

module ShopifyServices
  # Shopify Bulk Operations for customers.
  #
  #   ShopifyServices::CustomerBulkExportService.request(shop)    # starts an export (full, or incremental if the shop was pulled before)
  #   ShopifyServices::CustomerBulkExportService.refresh!(export) # polls Shopify, moves the export along
  #
  # The exported node has the same fields as CustomerPullService, so the loader can feed each
  # line to CustomerSingleDataSaveService unchanged.
  class CustomerBulkExportService
    CUSTOMER_NODE = <<~GQL.squish
      id firstName lastName phone email locale state lifetimeDuration verifiedEmail
      amountSpent { amount currencyCode } tags statistics { predictedSpendTier }
      defaultAddress { countryCodeV2 }
      addresses { id address1 address2 city company coordinatesValidated country countryCodeV2 firstName formatted formattedArea latitude longitude name lastName phone provinceCode province validationResultSummary zip }
      numberOfOrders lastOrder { id }
    GQL

    RUN_MUTATION = <<~GQL
      mutation ($query: String!) {
        bulkOperationRunQuery(query: $query) {
          bulkOperation { id status }
          userErrors { field message }
        }
      }
    GQL

    STATUS_QUERY = <<~GQL
      query ($id: ID!) {
        node(id: $id) {
          ... on BulkOperation { id status errorCode objectCount fileSize url }
        }
      }
    GQL

    class << self
      def bulk_query(since)
        filter = since.present? ? %[(query: "updated_at:>=#{since.utc.strftime('%Y-%m-%d')}")] : ''
        "{ customers#{filter} { edges { node { #{CUSTOMER_NODE} } } } }"
      end

      # Creates the export row and asks Shopify to build the file. Never raises: failures are recorded on the row.
      def request(shop)
        since = shop.initial_customer_pull_completed
        export = CustomerBulkExport.create!(
          shop: shop, shopify_domain: shop.shopify_domain, status: 'requested',
          since_at: since, requested_at: Time.current
        )
        begin
          payload = graphql(shop, RUN_MUTATION, 'query' => bulk_query(since))
          result = payload.dig('data', 'bulkOperationRunQuery') || {}
          errors = Array(result['userErrors']).map { |e| e['message'] }
          op = result['bulkOperation']
          if errors.present? || op.blank?
            export.fail!(errors.presence&.join('; ') || 'no bulk operation returned')
          else
            export.update!(bulk_operation_gid: op['id'], shopify_status: op['status'], status: 'running')
          end
        rescue StandardError => e
          export.fail!("#{e.class}: #{e.message}")
        end
        export
      end

      # Polls Shopify once. Returns the file url (or nil). Moves status:
      #   COMPLETED -> completed (or loaded straight away when the file is empty)
      #   FAILED / CANCELED / EXPIRED -> failed
      def refresh!(export)
        payload = graphql(export.shop, STATUS_QUERY, 'id' => export.bulk_operation_gid)
        op = payload.dig('data', 'node')
        if op.blank?
          export.fail!('bulk operation not found on Shopify')
          return nil
        end

        export.assign_attributes(
          shopify_status: op['status'],
          object_count: op['objectCount']&.to_i,
          file_size: op['fileSize']&.to_i
        )
        case op['status']
        when 'COMPLETED'
          if op['url'].blank? || export.object_count.to_i.zero?
            export.update!(status: 'loaded', loaded_at: Time.current)
            export.finalize_shop!
          else
            export.update!(status: 'completed') if CustomerBulkExport::AT_SHOPIFY.include?(export.status)
          end
        when 'FAILED', 'CANCELED', 'EXPIRED'
          export.fail!("Shopify bulk operation #{op['status']} #{op['errorCode']}".strip)
        else
          export.save!
        end
        op['url'].presence
      end

      private

      def graphql(shop, document, variables)
        shop.init_session
        client = ShopifyAPI::GraphQL.client
        response = client.query(client.parse(document), variables: variables)
        payload = response.to_h
        raise "Shopify GraphQL errors: #{payload['errors'].to_json.truncate(500)}" if payload['errors'].present?

        payload
      end
    end
  end
end
