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

    CANCEL_MUTATION = <<~GQL
      mutation ($id: ID!) {
        bulkOperationCancel(id: $id) {
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

      def request(shop)
        since = shop.initial_customer_pull_completed
        expected = begin
          fresh_count(shop)
        rescue StandardError
          nil
        end
        export = CustomerBulkExport.create!(
          shop: shop, shopify_domain: shop.shopify_domain, status: 'requested',
          since_at: since, requested_at: Time.current, progress_at: Time.current,
          expected_count: expected
        )
        CustomerSyncState.mark_running!(shop.id)
        begin
          payload = graphql(shop, RUN_MUTATION, 'query' => bulk_query(since))
          result = payload.dig('data', 'bulkOperationRunQuery') || {}
          errors = Array(result['userErrors']).map { |e| e['message'] }
          op = result['bulkOperation']
          if errors.present? || op.blank?
            export.fail!(errors.presence&.join('; ') || 'no bulk operation returned', count_failure: !busy?(errors))
          else
            export.update!(bulk_operation_gid: op['id'], shopify_status: op['status'], status: 'running')
          end
        rescue StandardError => e
          export.fail!("#{e.class}: #{e.message}")
        end
        export
      end

      def cancel!(export)
        return if export.bulk_operation_gid.blank?

        graphql(export.shop, CANCEL_MUTATION, 'id' => export.bulk_operation_gid)
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

        progressed = op['objectCount'].to_i > export.object_count.to_i
        export.assign_attributes(
          shopify_status: op['status'],
          object_count: op['objectCount']&.to_i,
          file_size: op['fileSize']&.to_i
        )
        export.progress_at = Time.current if progressed
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

      def fresh_count(shop)
        count = ShopifyServices::CustomerCountFetchService.call(shop)
        return CustomerSyncState.for_shop(shop.id).shopify_customer_count unless count.is_a?(Integer)

        shop.update_column(:customer_count, count)
        CustomerSyncState.record_count!(shop, count)
        count
      end

      def busy?(errors)
        errors.any? { |m| m.to_s.match?(/already in progress|in progress/i) }
      end

      # 30s read-timeout: bulk export/poll calls run in the background (no live buyer waiting),
      # but the shared ShopifyAPI::GraphQL client has no timeout of its own and will otherwise
      # hang indefinitely on a non-responding Shopify request, wedging the single-concurrency
      # global_data_pull worker. Same mechanism as CodFormShopifyTimeout's own 12s checkout-path
      # timeout (lib/cod_form_shopify_timeout.rb); see that file's comment for why this is a
      # thread-local opt-in rather than a client-wide default.
      GRAPHQL_READ_TIMEOUT = 30

      def graphql(shop, document, variables)
        shop.init_session
        client = ShopifyAPI::GraphQL.client
        response = CodFormShopifyTimeout.with(GRAPHQL_READ_TIMEOUT) do
          client.query(client.parse(document), variables: variables)
        end
        payload = response.to_h
        raise "Shopify GraphQL errors: #{payload['errors'].to_json.truncate(500)}" if payload['errors'].present?

        payload
      end
    end
  end
end
