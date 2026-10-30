module ShopifyJobs
  class PartialOrderEditJob < ApplicationJob
    def perform(shop_id, shopify_order_id, partial_variant_ids, retry_flag = false)
      shop = Shop.find_by(id: shop_id)
      return unless shop&.setting
      
      order_confirmation = OrderConfirmation.find_by(order_id: shopify_order_id)
      return unless order_confirmation
      
      # Handle nil or empty partial_variant_ids - get from order_confirmation if blank
      if partial_variant_ids.blank?
        # Try to get from order_confirmation.partial_payment_variants
        if order_confirmation.partial_payment_variants.present?
          begin
            partial_variant_ids = JSON.parse(order_confirmation.partial_payment_variants).map(&:to_s)
          rescue JSON::ParserError => e
            Rails.logger.error "Failed to parse partial_payment_variants from order_confirmation #{order_confirmation.id}: #{e.message}"
            partial_variant_ids = []
          end
        else
          partial_variant_ids = []
        end
      else
        begin
          partial_variant_ids = JSON.parse(partial_variant_ids).map(&:to_s)
        rescue JSON::ParserError => e
          Rails.logger.error "Failed to parse partial_variant_ids parameter: #{e.message}"
          # Try to get from order_confirmation as fallback
          if order_confirmation.partial_payment_variants.present?
            begin
              partial_variant_ids = JSON.parse(order_confirmation.partial_payment_variants).map(&:to_s)
            rescue JSON::ParserError
              partial_variant_ids = []
            end
          else
            partial_variant_ids = []
          end
        end
      end
      
      # v2 bundle services re-derive the partial line items from the Shopify order
      # itself and are called with (shop, order_id) only, so blank variant ids are
      # expected there. Only the v1 services consume partial_variant_ids.
      flow_version_two = shop.setting.partial_payment_flow_version == 2

      if partial_variant_ids.blank? && !flow_version_two
        SlackNotifyJob.perform_async(
          ":warning: (#{Rails.env})\nPartialOrderEditJob SKIPPED - No partial_variant_ids found\nID: #{order_confirmation.id}\nOrder: #{shopify_order_id}\nShop: #{shop.shopify_domain}\nOrder URL: #{order_confirmation.order_status_url}\nStatus: #{order_confirmation.status}\nNote: partial_variant_ids parameter was blank and order_confirmation.partial_payment_variants is also blank"
        )
        Rails.logger.warn "PartialOrderEditJob skipped for order #{shopify_order_id}: no partial_variant_ids found"
        ShopifyServices::PartialOrderMappingService.call(order_confirmation.shop, order_confirmation.order_id)
        return
      end
      
      # Bundle SAME_ORDER flow: skip if already partially paid, and keep any step marker
      # (COD-Partial-Payment-Received-*) so the service resumes from the last committed step
      bundle_same_order = flow_version_two && shop.setting.partial_payment_flow != 'NEW_ORDER'
      if bundle_same_order && order_confirmation.status == 'COD-Partial-Payment-Received'
        Rails.logger.info "PartialOrderEditJob skipped for order #{shopify_order_id}: already COD-Partial-Payment-Received"
        return
      end
      bundle_step_marker = bundle_same_order && ShopifyServices::PartialOrderEditService::Bundle.step_status?(order_confirmation.status)

      # Update status to in-progress before processing (a kept marker is touched instead, so
      # PartialPaymentCheckJob sees it as fresh and doesn't queue another run)
      if bundle_step_marker
        order_confirmation.touch
      else
        order_confirmation.update!(status: 'Partial-Payment-In-Progress')
      end
      
      # Determine failure status based on retry flag
      failure_status = retry_flag ? 'Partial-Payment-Retry-Failed' : 'Partial-Payment-Process-Failed'
      
      if flow_version_two
        if shop.setting.partial_payment_flow == 'NEW_ORDER'
          resp = ShopifyServices::PartialOrderCreateService::Bundle.call(shop, shopify_order_id)
          
          # Recheck status after service call
          order_confirmation.reload
          if order_confirmation.status != 'COD-Partial-Payment-Received'
            order_confirmation.update!(status: failure_status)
            SlackNotifyJob.perform_async(
              ":warning: (#{Rails.env})\nBundle NEW_ORDER PartialOrderEditJob FAILED\nID: #{order_confirmation.id}\nOrder: #{shopify_order_id}\nShop: #{shop.shopify_domain}\nOrder URL: #{order_confirmation.order_status_url}\nStatus: #{order_confirmation.status}\nResponse: #{resp.inspect}"
            )
          else
            report_remaining_amount_to_meta(shop, order_confirmation, shopify_order_id)
            # report_remaining_amount_to_google(shop, order_confirmation, shopify_order_id)
            deduct_free_wallet_partial_payment(shop, order_confirmation)
            SlackNotifyJob.perform_async(
              ":heart: (#{Rails.env})\nBundle NEW_ORDER PartialOrderEditJob Completed\nID: #{order_confirmation.id}\nOrder: #{shopify_order_id}\nShop: #{shop.shopify_domain}\nOrder URL: #{order_confirmation.order_status_url}\nResponse: #{resp.inspect}"
            )
          end
        else
          # SAME_ORDER flow - edits the same order with bundle flattening
          resp = ''
          if retry_flag
            resp = ShopifyServices::PartialOrderEditService::BundleTwoCommit.call(shop, shopify_order_id)
          else  
            resp = ShopifyServices::PartialOrderEditService::Bundle.call(shop, shopify_order_id)
          end
          
          # Recheck status after service call
          order_confirmation.reload
          if order_confirmation.status != 'COD-Partial-Payment-Received'
            bundle_service = ShopifyServices::PartialOrderEditService::Bundle
            if !bundle_service.step_status?(order_confirmation.status)
              order_confirmation.update!(status: failure_status)
            elsif retry_flag && !order_confirmation.status.end_with?(bundle_service::RETRY_FAILED_SUFFIX)
              # Keep the marker (so a manual retry still resumes) but stop PartialPaymentCheckJob re-queueing it
              order_confirmation.update!(status: "#{order_confirmation.status}#{bundle_service::RETRY_FAILED_SUFFIX}")
            end
            SlackNotifyJob.perform_async(
              ":warning: (#{Rails.env})\nBundle SAME_ORDER PartialOrderEditJob FAILED\nID: #{order_confirmation.id}\nOrder: #{shopify_order_id}\nShop: #{shop.shopify_domain}\nOrder URL: #{order_confirmation.order_status_url}\nStatus: #{order_confirmation.status}\nResponse: #{resp.inspect}"
            )
          else
            report_remaining_amount_to_meta(shop, order_confirmation, shopify_order_id)
            # report_remaining_amount_to_google(shop, order_confirmation, shopify_order_id)
            deduct_free_wallet_partial_payment(shop, order_confirmation)
            SlackNotifyJob.perform_async(
              ":heart: (#{Rails.env})\nBundle SAME_ORDER PartialOrderEditJob Completed\nID: #{order_confirmation.id}\nOrder: #{shopify_order_id}\nShop: #{shop.shopify_domain}\nOrder URL: #{order_confirmation.order_status_url}\nResponse: #{resp.inspect}"
            )
          end
        end
      elsif shop.setting.partial_payment_flow == 'SAME_ORDER'
        resp = ''
        if retry_flag
          resp = ShopifyServices::PartialOrderEditTwoCommitService.call(shop, shopify_order_id, partial_variant_ids)
        else  
          resp = ShopifyServices::PartialOrderEditService.call(shop, shopify_order_id, partial_variant_ids)
        end
        # Recheck status after service call
        order_confirmation.reload
        if order_confirmation.status != 'COD-Partial-Payment-Received'
          order_confirmation.update!(status: failure_status)
          SlackNotifyJob.perform_async(
            ":warning: (#{Rails.env})\nSAME_ORDER PartialOrderEditJob FAILED\nID: #{order_confirmation.id}\nOrder: #{shopify_order_id}\nShop: #{shop.shopify_domain}\nVariants: #{partial_variant_ids}\nOrder URL: #{order_confirmation.order_status_url}\nStatus: #{order_confirmation.status}\nResponse: #{resp.inspect}"
          )
        else
          report_remaining_amount_to_meta(shop, order_confirmation, shopify_order_id)
          # report_remaining_amount_to_google(shop, order_confirmation, shopify_order_id)
          deduct_free_wallet_partial_payment(shop, order_confirmation)
          SlackNotifyJob.perform_async(
            ":heart: (#{Rails.env})\nSAME_ORDER PartialOrderEditJob Completed\nID: #{order_confirmation.id}\nOrder: #{shopify_order_id}\nShop: #{shop.shopify_domain}\nVariants: #{partial_variant_ids}\nOrder URL: #{order_confirmation.order_status_url}\nResponse: #{resp.inspect}"
          )
        end
      else
        # Check if all line items have "Partial Payment for" in title before calling service
        unless all_line_items_have_partial_payment?(shop, shopify_order_id)
          Rails.logger.warn "Not all line items contain 'Partial Payment for' - skipping PartialOrderCreateService"
          order_confirmation.update!(status: 'Partial-Payment-Order-Skipped')
          SlackNotifyJob.perform_async(
            ":warning: (#{Rails.env})\nNEW Order PartialOrderEditJob SKIPPED - Not all items are partial payment\nID: #{order_confirmation.id}\nOrder: #{shopify_order_id}\nShop: #{shop.shopify_domain}\nVariants: #{partial_variant_ids}"
          )
          return
        end
        
        resp = ShopifyServices::PartialOrderCreateService.call(shop, shopify_order_id, partial_variant_ids)
        
        # Recheck status after service call
        order_confirmation.reload
        if order_confirmation.status != 'COD-Partial-Payment-Received'
          order_confirmation.update!(status: failure_status)
          SlackNotifyJob.perform_async(
            ":warning: (#{Rails.env})\nNEW Order PartialOrderEditJob FAILED\nID: #{order_confirmation.id}\nOrder: #{shopify_order_id}\nShop: #{shop.shopify_domain}\nVariants: #{partial_variant_ids}\nStatus: #{order_confirmation.status}\nResponse: #{resp.inspect}"
          )
        else
          report_remaining_amount_to_meta(shop, order_confirmation, shopify_order_id)
          # report_remaining_amount_to_google(shop, order_confirmation, shopify_order_id)
          deduct_free_wallet_partial_payment(shop, order_confirmation)
          SlackNotifyJob.perform_async(
            ":heart: (#{Rails.env})\nNEW Order PartialOrderEditJob Completed\nID: #{order_confirmation.id}\nOrder: #{shopify_order_id}\nShop: #{shop.shopify_domain}\nResponse: #{resp.inspect}"
          )
        end
      end

      refresh_order_metric(shop, shopify_order_id) if order_confirmation.reload.status == 'COD-Partial-Payment-Received'
    end

    private

    def refresh_order_metric(shop, shopify_order_id)
      shop.init_session
      order = ShopifyAPI::Order.find(shopify_order_id)
      OrderMetrics::UpsertService.call(shop, JSON.parse(order.to_json)) if order.present?
    rescue StandardError => e
      Rails.logger.error "[OrderMetrics] partial refresh failed shop_id=#{shop.id} order=#{shopify_order_id} #{e.class}: #{e.message}"
    end

    def deduct_free_wallet_partial_payment(shop, order_confirmation)
      return if shop.charge_id.present?

      NetworkServices::FreeWalletService.deduct_partial_payment(shop, order_confirmation)
    rescue StandardError => e
      Rails.logger.error "deduct_free_wallet_partial_payment error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    end

    # Calls Meta Conversion API with the order that has the remaining amount (e.g. ₹900 if ₹100 was paid on ₹1000 order).
    # Only runs when pixel_id and pixel_token are configured in settings.
    def report_remaining_amount_to_meta(shop, order_confirmation, shopify_order_id)
      setting = shop.setting
      return unless setting.pixel_id.present? && setting.pixel_token.present?
      return unless NetworkServices::MetaConversionService.meta_conversion_enabled?(setting)

      # The web pixel already reports the FULL order value at checkout_completed (it reads
      # _codkOriginalTotal), so adding the remaining balance here would double-count revenue.
      if setting.meta_events_active?
        Rails.logger.info(
          "[Codk::PartialPayment] Meta CAPI remaining_balance skipped — meta_events_enabled " \
          "shop=#{shop.shopify_domain} order=#{shopify_order_id}"
        )
        return
      end

      # Order representing remaining balance: for NEW_ORDER flow it's the new order (draft_order_id); else the edited order
      order_id = order_confirmation.draft_order_id.presence || shopify_order_id
      return if order_id.blank?

      shop.init_session
      order = ShopifyAPI::Order.find(order_id)
      return unless order.present?

      # Remaining amount = balance due (Shopify total_outstanding, current_total_price, total_price are tax-inclusive).
      remaining_amount = if order.respond_to?(:total_outstanding) && order.total_outstanding.present?
        order.total_outstanding.to_s.to_f
      end
      remaining_amount ||= if order.respond_to?(:current_total_price) && order.current_total_price.present?
        order.current_total_price.to_s.to_f
      else
        order.total_price.to_s.to_f
      end

      orig = nil
      if shopify_order_id.to_s != order.id.to_s
        begin
          orig = ShopifyAPI::Order.find(shopify_order_id)
        rescue StandardError => e
          Rails.logger.warn "[Codk::PartialPayment] Meta CAPI: could not load original order #{shopify_order_id} for context: #{e.message}"
        end
      end

      result = NetworkServices::MetaConversionService.call_with_context(
        order,
        remaining_amount,
        setting,
        shop: shop,
        fallback_order: orig,
      )

      return if result.is_a?(Hash) && result["skipped"]

      meta_msg = ":chart_with_downwards_trend: (#{Rails.env}) *Meta Conversion* (remaining amount)\n" \
                 "Order: #{order_id} | Shop: #{shop.shopify_domain} | Amount: #{remaining_amount}\n" \
                 "*Result:* #{result.is_a?(Hash) ? result.to_json : result.inspect}"
      SlackNotifyJob.perform_async(meta_msg)

      if result.is_a?(Hash) && result["error"].present?
        Rails.logger.warn "MetaConversionService (remaining amount): #{result['error']}"
      else
        Rails.logger.info "MetaConversionService sent remaining amount #{remaining_amount} for order #{order_id}"
      end
    rescue StandardError => e
      Rails.logger.error "report_remaining_amount_to_meta error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    end

    # Calls Google Ads Conversion API with the remaining amount for partial payment orders.
    # Only runs when conversion_tracking and credentials are configured (same pattern as Meta).
    def report_remaining_amount_to_google(shop, order_confirmation, shopify_order_id)
      setting = shop.setting
      return unless setting&.conversion_tracking != false

      order_id = order_confirmation.draft_order_id.presence || shopify_order_id
      return if order_id.blank?

      shop.init_session
      order = ShopifyAPI::Order.find(order_id)
      return unless order.present?

      remaining_amount = if order.respond_to?(:total_outstanding) && order.total_outstanding.present?
        order.total_outstanding.to_s.to_f
      end
      remaining_amount ||= if order.respond_to?(:current_total_price) && order.current_total_price.present?
        order.current_total_price.to_s.to_f
      else
        order.total_price.to_s.to_f
      end

      gclid = NetworkServices::GoogleConversionService.gclid_from_landing_site(order.landing_site)
      result = NetworkServices::GoogleConversionService.call_partial(
        order,
        remaining_amount,
        setting,
        order_id: order_id.to_s,
        gclid: gclid
      )

      google_msg = ":chart_with_downwards_trend: (#{Rails.env}) *Google Conversion* (remaining amount)\n" \
                  "Order: #{order_id} | Shop: #{shop.shopify_domain} | Amount: #{remaining_amount}\n" \
                  "*Result:* #{result.is_a?(Hash) ? result.to_json : result.inspect}"
      SlackNotifyJob.perform_async(google_msg)

      if result.is_a?(Hash) && result["error"].present?
        Rails.logger.warn "GoogleConversionService (remaining amount): #{result['error']}"
      else
        Rails.logger.info "GoogleConversionService sent remaining amount #{remaining_amount} for order #{order_id}"
      end
    rescue StandardError => e
      Rails.logger.error "report_remaining_amount_to_google error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    end

    def all_line_items_have_partial_payment?(shop, order_id)
      shop.init_session
      client = ShopifyAPI::GraphQL.client
      
      query = client.parse <<-'GRAPHQL'
        query($id:ID!) {
          order(id:$id){
            id
            lineItems(first:50){
              edges{
                node{
                  id
                  quantity
                  title
                  name
                }
              }
            }
          }
        }
      GRAPHQL
      
      variables = {
        id: "gid://shopify/Order/#{order_id}"
      }
      
      resp = client.query(query, variables: variables)
      
      unless resp&.data&.order&.line_items&.edges.present?
        Rails.logger.warn "No line items found in order #{order_id}"
        return false
      end
      
      line_items_edges = resp.data.order.line_items.edges
      
      # Check if all line items have "Partial Payment for" in title or name
      all_have_partial_payment = line_items_edges.all? do |edge|
        node = edge.node
        title = node.title || node.name || ""
        title.include?("Partial Payment for")
      end
      
      Rails.logger.info "Order #{order_id} - All items have 'Partial Payment for': #{all_have_partial_payment} (#{line_items_edges.count} line items)"
      
      all_have_partial_payment
    rescue => e
      Rails.logger.error "Error checking line items for partial payment: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      false
    end
  end
end