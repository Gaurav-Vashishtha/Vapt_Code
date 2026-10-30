# frozen_string_literal: true

module ShopifyServices
  class CodOrderCreateService
    attr_reader :shop, :cart_data, :shipping_address, :buyer_identity, :cod_fee, :shipping_line_handle, :otp_verified

    # form_context (COD Form module, docs/cod-form/ARCHITECTURE.md F.4) is nil for every existing
    # caller: the Express path then behaves, and builds its draft order, exactly as before.
    # Keys: :draft_input (complete DraftOrderInput), :expected_total_cents,
    # :tolerance_cents.
    def initialize(shop, cart_data, shipping_address, buyer_identity, cod_fee = nil, shipping_line_handle = nil, otp_verified = false, meta_click_data: nil, client_context: nil, campaign_attribution: nil, form_context: nil)
      @shop = shop
      @form_context = form_context.is_a?(Hash) ? form_context : nil
      @cart_data = cart_data
      @shipping_address = shipping_address
      @buyer_identity = buyer_identity
      @cod_fee = cod_fee
      @shipping_line_handle = shipping_line_handle
      @otp_verified = ActiveModel::Type::Boolean.new.cast(otp_verified)
      # ActionController::Parameters is not a Hash — must permit or Meta CAPI drops fbp/fbc.
      if meta_conversion_enabled?
        @meta_click_data = NetworkServices::MetaConversionService.coerce_meta_click_hash(meta_click_data)
        @client_context = client_context.is_a?(Hash) ? client_context : {}
        @campaign_attribution = CampaignAttributionHelper.normalize(campaign_attribution)
      else
        @meta_click_data = {}
        @client_context = {}
        @campaign_attribution = {}
      end
      @client = nil
    end

    def self.call(shop, cart_data, shipping_address, buyer_identity, cod_fee = nil, shipping_line_handle = nil, otp_verified = false, meta_click_data: nil, client_context: nil, campaign_attribution: nil, form_context: nil)
      new(shop, cart_data, shipping_address, buyer_identity, cod_fee, shipping_line_handle, otp_verified,
          meta_click_data: meta_click_data, client_context: client_context, campaign_attribution: campaign_attribution,
          form_context: form_context).call
    end

    def call
      shop.init_session
      @client = ShopifyAPI::GraphQL.client

      # Create draft order
      draft_order_response = create_draft_order

      if draft_order_response&.data&.draft_order_create&.user_errors&.any?
        errors = draft_order_response.data.draft_order_create.user_errors
        error_messages = errors.map { |e| "#{e.field}: #{e.message}" }.join(", ")
        Rails.logger.error "Error creating draft order: #{error_messages}"
        return { error: "Error creating draft order", errors: errors, code: "draft_user_errors" }
      end

      unless draft_order_response&.data&.draft_order_create&.draft_order
        Rails.logger.error "Failed to create draft order: shop_id=#{shop.id}"
        return { error: "Failed to create draft order", code: "draft_user_errors" }
      end

      draft_order_gid = draft_order_response.data.draft_order_create.draft_order.id
      draft_total_cents = draft_total_cents_from(draft_order_response)

      # COD Form only: the draft total must equal the total the buyer confirmed (ORD-3).
      if @form_context && form_total_changed?(draft_total_cents)
        delete_draft_order(draft_order_gid)
        return { error: "Draft order total changed", code: "total_changed",
                 draft_total_cents: draft_total_cents, draft_order_id: draft_order_gid }
      end

      # Complete draft order to create real order
      order_id = create_order_from_draft_order(draft_order_response)

      unless order_id
        Rails.logger.error "Failed to create order from draft order"
        failure = { error: "Failed to create order from draft order", code: "complete_failed",
                    draft_total_cents: draft_total_cents, draft_order_id: draft_order_gid }
        # COD Form only: the completion call raised (time-out, 5xx), so Shopify may have created
        # the order all the same. The form must not let the buyer create a second one.
        failure[:outcome_unknown] = true if @form_context && @complete_raised
        return failure
      end

      # Fetch order details for order_status_url (redirect after success)
      order = fetch_created_order(order_id)
      order_status_url = order.respond_to?(:order_status_url) ? order.order_status_url : nil

      # The form's draft input already carries the verification tag (F.3).
      add_verification_tag_if_verified(shop, order_id) unless @form_context

      report_purchase_to_meta_if_configured(
        shop,
        order,
        meta_click_data: @meta_click_data,
        client_context: @client_context,
        campaign_attribution: @campaign_attribution
      )
      # report_purchase_to_google_if_configured(shop, order)

      {
        success: true,
        order_id: order_id,
        order_number: order&.order_number,
        order_name: order&.name,
        total_price: order&.total_price,
        currency_code: order&.currency,
        order_status_url: order_status_url,
        draft_total_cents: draft_total_cents,
        draft_order_id: draft_order_gid
      }
    rescue StandardError => e
      Rails.logger.error "Error in CodOrderCreateService: #{e.message} #{e.backtrace.first(5).join("\n")}"
      { error: e.message, code: "exception" }
    end

    private

    # Express (no form_context): exactly as before, an error here fails the call.
    # COD Form: the order exists once the draft is completed; failing to read its details must
    # not report the order as failed (the buyer would retry and create a second order), so the
    # form path answers success with the order id alone.
    def fetch_created_order(order_id)
      ShopifyAPI::Order.find(order_id)
    rescue StandardError => e
      raise unless @form_context

      Rails.logger.error "CodOrderCreateService: order #{order_id} created, details not read: #{e.class}"
      nil
    end

    def meta_conversion_enabled?
      s = shop.setting
      return true if s.nil?
      return true unless s.has_attribute?(:conversion_tracking)

      s.conversion_tracking != false
    end

    # Report purchase to Meta Conversion API (same pattern as Google).
    def report_purchase_to_meta_if_configured(shop, order, meta_click_data: {}, client_context: {}, campaign_attribution: {})
      if @form_context
        Rails.logger.info "MetaConversionService skipped for COD form order #{order&.id}"
        return
      end

      setting = shop.setting
      return unless setting&.pixel_id.present? && setting&.pixel_token.present?
      return unless NetworkServices::MetaConversionService.meta_conversion_enabled?(setting)

      result = NetworkServices::MetaConversionService.call_purchase(
        order,
        setting,
        meta_click_data: meta_click_data,
        client_context: client_context,
        campaign_attribution: campaign_attribution
      )
      return if result.is_a?(Hash) && result["skipped"]

      # No payload (hashed PII, click ids) in logs or Slack; error-only alerts (NFR-7).
      if result.is_a?(Hash) && result["error"].present?
        Rails.logger.warn "MetaConversionService (COD form purchase): #{result['error']}"
        SlackNotifyJob.perform_async(
          ":x: *MetaConversionService (COD)* — failure\n" \
          "Shop: #{shop.shopify_domain} | Order: #{order.id}\n" \
          "Error: #{result['error']}"
        )
      else
        Rails.logger.info "MetaConversionService sent purchase for COD order #{order.id}"
      end
    rescue StandardError => e
      Rails.logger.error "report_purchase_to_meta_if_configured error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      SlackNotifyJob.perform_async(
        ":x: *MetaConversionService (COD)* — exception\n" \
        "Shop: #{shop.shopify_domain} | Order: #{order&.id}\n" \
        "Error: #{e.class}: #{e.message}"
      )
    end

    # GCLID (Google Click ID) and related params link the conversion to an ad click. Official docs:
    # https://developers.google.com/google-ads/api/docs/conversions/upload-online
    # https://developers.google.com/google-ads/api/reference/rpc/v22/ClickConversion (gclid field)
    # Get gclid from order.landing_site (Shopify REST Order resource includes landing_site by default).
    def report_purchase_to_google_if_configured(shop, order)
      setting = shop.setting
      return unless setting&.conversion_tracking != false
      landing_params = NetworkServices::GoogleConversionService.params_from_landing_site(order.landing_site)
      result = NetworkServices::GoogleConversionService.call_purchase(
        order,
        setting,
        gclid: landing_params[:gclid],
        gbraid: landing_params[:gbraid],
        wbraid: landing_params[:wbraid],
        gad_campaignid: landing_params[:gad_campaignid],
        gad_source: landing_params[:gad_source]
      )

      if result.is_a?(Hash) && result["error"].present?
        Rails.logger.warn "GoogleConversionService (COD form purchase): #{result['error']}"
      else
        Rails.logger.info "GoogleConversionService sent purchase for COD order #{order.id}"
      end
    rescue StandardError => e
      Rails.logger.error "report_purchase_to_google_if_configured error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    end

    def build_draft_order_note
      base = "COD order created from cart"
      base = "#{base} — OTP verified" if otp_verified
      campaign_txt = CampaignAttributionHelper.format_note_lines(@campaign_attribution)
      return base if campaign_txt.blank?

      "#{base}\n\n#{campaign_txt}"
    end

    def build_draft_order_tags
      tags = ["COD", "Created-From-COD-King"]
      if otp_verified
        verification_tag = shop.setting&.verification_tag.presence || "✅ COD-Verified"
        tags << verification_tag
      end
      tags
    end

    def add_verification_tag_if_verified(shop, order_id)
      return unless otp_verified
      verification_tag = shop.setting&.verification_tag.presence || "✅ COD-Verified"
      return if verification_tag.blank?
      ShopifyServices::OrderTagPostService.call(shop, order_id, verification_tag)
    rescue StandardError => e
      Rails.logger.error "CodOrderCreateService: failed to add verification tag to order #{order_id}: #{e.message}"
    end

    def create_draft_order
      query = @client.parse <<-'GRAPHQL'
        mutation ($input: DraftOrderInput!) {
          draftOrderCreate(input: $input) {
            draftOrder {
              id
              invoiceUrl
              totalPrice
              status
              name
              currencyCode
              totalPriceSet {
                presentmentMoney {
                  amount
                  currencyCode
                }
              }
            }
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL

      # COD Form: the complete, server-computed DraftOrderInput is passed in (F.3 / F.4).
      if @form_context
        Rails.logger.info "Creating COD form draft order: shop_id=#{shop.id} lines=#{Array(@form_context.dig(:draft_input, 'lineItems')).size}"
        return @client.query(query, variables: { input: @form_context[:draft_input] })
      end

      # Format phone number to E.164 format (required by Shopify)
      formatted_phone = format_phone_number(buyer_identity[:phone])

      variables = {
        input: {
          lineItems: build_line_items,
          shippingAddress: build_shipping_address,
          billingAddress: build_shipping_address, # Use shipping as billing for COD
          email: buyer_identity[:email].presence,
          phone: formatted_phone,
          note: build_draft_order_note,
          tags: build_draft_order_tags,
          taxExempt: false,
          appliedDiscount: build_applied_discount
        }
      }

      attrs = CampaignAttributionHelper.shopify_custom_attributes_blob(@campaign_attribution)
      variables[:input][:customAttributes] = attrs if attrs.present?

      # Add shipping line with COD fee if present
      shipping_line = build_shipping_line
      variables[:input][:shippingLine] = shipping_line if shipping_line.present?

      # Add customer if we have email/phone to match existing customer
      if buyer_identity[:email].present? || buyer_identity[:phone].present?
        customer_id = find_or_create_customer
        variables[:input][:customerId] = customer_id if customer_id.present?
      end

      Rails.logger.info "Creating COD draft order: shop_id=#{shop.id} lines=#{Array(variables[:input][:lineItems]).size}"
      resp = @client.query(query, variables: variables)
      created = resp&.data&.draft_order_create&.draft_order
      Rails.logger.info "Draft order response: shop_id=#{shop.id} draft_order_id=#{created&.id} total=#{created&.total_price}"
      resp
    end

    # Draft total in presentment currency, integer cents (nil when Shopify did not return it).
    def draft_total_cents_from(draft_order_response)
      money = draft_order_response.data.draft_order_create.draft_order.total_price_set&.presentment_money
      return nil if money.nil? || money.amount.nil?

      (BigDecimal(money.amount.to_s) * 100).round.to_i
    rescue StandardError
      nil
    end

    def form_total_changed?(draft_total_cents)
      expected = @form_context[:expected_total_cents]
      return false if expected.nil? || draft_total_cents.nil?

      (draft_total_cents - expected.to_i).abs > @form_context[:tolerance_cents].to_i
    end

    def delete_draft_order(draft_order_gid)
      query = @client.parse <<-'GRAPHQL'
        mutation ($input: DraftOrderDeleteInput!) {
          draftOrderDelete(input: $input) {
            deletedId
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL
      @client.query(query, variables: { input: { id: draft_order_gid } })
    rescue StandardError => e
      Rails.logger.error "CodOrderCreateService: failed to delete draft order #{draft_order_gid}: #{e.message}"
    end

    def build_line_items
      items = cart_data[:items] || cart_data['items'] || []
      gift_lines = FreeGifts::OrderLines.new(@shop, items)
      regular_line_items(gift_lines.regular_items) + gift_lines.gift_line_items
    end

    def regular_line_items(items)
      items.map do |item|
        variant_id = item[:variant_id] || item['variant_id'] || item[:id] || item['id']
        quantity = item[:quantity] || item['quantity'] || 1
        
        line_item = {
          variantId: "gid://shopify/ProductVariant/#{variant_id}",
          quantity: quantity.to_i
        }

        Upsells.tag_line_item!(line_item, item)

        # Apply line item discounts if present
        if item[:line_level_discount_allocations] || item['line_level_discount_allocations']
          discounts = item[:line_level_discount_allocations] || item['line_level_discount_allocations']
          total_discount_cents = discounts.sum { |d| d[:amount] || d['amount'] || 0 }
          
          if total_discount_cents > 0
            # Convert from cents to decimal
            total_discount_amount = (total_discount_cents / 100.0).to_f
            # Shopify applies FIXED_AMOUNT discounts per-unit, so divide by quantity
            per_unit_discount = quantity.to_i > 0 ? (total_discount_amount / quantity.to_f) : total_discount_amount
            
            # Get discount title/description from first discount allocation
            discount_title = discounts.first&.dig(:discount_application, :title) || 
                           discounts.first&.dig('discount_application', 'title') ||
                           discounts.first&.dig(:discount_application, :description) ||
                           discounts.first&.dig('discount_application', 'description') ||
                           'Discount'
            
            line_item[:appliedDiscount] = {
              valueType: 'FIXED_AMOUNT',
              value: per_unit_discount.round(2),
              title: discount_title,
              description: discount_title
            }
          end
        end

        line_item
      end
    end

    def build_shipping_address
      phone = shipping_address[:phone].presence || shipping_address['phone'].presence || format_phone_number(buyer_identity[:phone])
      {
        firstName: shipping_address[:first_name] || shipping_address['first_name'] || '',
        lastName: shipping_address[:last_name] || shipping_address['last_name'] || '',
        address1: shipping_address[:address1] || shipping_address['address1'] || '',
        address2: shipping_address[:address2] || shipping_address['address2'] || '',
        city: shipping_address[:city] || shipping_address['city'] || '',
        province: shipping_address[:province] || shipping_address['province'] || shipping_address[:state] || shipping_address['state'] || '',
        zip: shipping_address[:zip] || shipping_address['zip'] || shipping_address[:postal_code] || shipping_address['postal_code'] || '',
        country: shipping_address[:country] || shipping_address['country'] || '',
        phone: phone
      }.compact
    end

    def build_applied_discount
      discount_applications = cart_data[:cart_level_discount_applications] || cart_data['cart_level_discount_applications'] || []
      return nil if discount_applications.empty?

      allocated_cents = discount_applications.sum do |d|
        (d[:total_allocated_amount] || d['total_allocated_amount']).to_f
      end
      titles = discount_applications.filter_map { |d| d[:title] || d['title'] || d[:description] || d['description'] }
      discount_title = titles.uniq.join(', ').presence || 'Discount'

      if allocated_cents.positive?
        return {
          valueType: 'FIXED_AMOUNT',
          value: (allocated_cents / 100.0).round(2),
          description: discount_title
        }
      end

      discount = discount_applications.first
      value_type = discount[:value_type] || discount['value_type']
      value = (discount[:value] || discount['value']).to_f

      if value_type == 'percentage'
        { valueType: 'PERCENTAGE', value: value.round(2), description: discount_title }
      else
        { valueType: 'FIXED_AMOUNT', value: value.round(2), description: discount_title }
      end
    end

    def build_shipping_line
      currency_code = cart_data[:currency_code] || cart_data['currency_code'] || 'INR'
      shipping_price = 0
      shipping_title_parts = []
      
      # Get shipping rate details if provided
      if @shipping_rate_details.present?
        shipping_details = if @shipping_rate_details.is_a?(Hash)
          @shipping_rate_details
        elsif @shipping_rate_details.is_a?(String)
          JSON.parse(@shipping_rate_details) rescue {}
        else
          {}
        end
        
        shipping_price = shipping_details['price'] || shipping_details[:price] || 0
        shipping_title = shipping_details['title'] || shipping_details[:title] || 'Shipping'
        shipping_title_parts << shipping_title
      end
      
      # Add COD fee if present
      cod_fee_amount = 0
      if cod_fee.present? && cod_fee.to_f > 0
        cod_fee_amount = cod_fee.to_f
        shipping_title_parts << "COD Fee"
      end
      
      # Combine both charges
      total_amount = shipping_price.to_f + cod_fee_amount
      
      # If no charges, return nil
      return nil if total_amount <= 0
      
      # Build combined title
      combined_title = shipping_title_parts.join(" + ")
      
      shipping_line = {
        priceWithCurrency: {
          amount: total_amount.to_s,
          currencyCode: currency_code
        },
        title: combined_title
      }
      
      return shipping_line
    end

    def format_phone_number(phone)
      return nil unless phone.present?
      
      # Remove all non-digit characters except +
      cleaned = phone.to_s.gsub(/[^\d+]/, '')
      
      # If it doesn't start with +, add it (assuming it's a valid number)
      if cleaned.present? && !cleaned.start_with?('+')
        cleaned = "+#{cleaned}"
      end
      
      cleaned.presence
    end

    def find_or_create_customer
      # Shopify will automatically match/create customer based on email/phone
      # We can optionally find existing customer here, but Shopify handles it
      # Return nil to let Shopify handle customer creation/matching
      nil
    end

    def create_order_from_draft_order(draft_order_response)
      draft_order_id = draft_order_response.data.draft_order_create.draft_order.id
      draft_order_numeric_id = draft_order_id.gsub('gid://shopify/DraftOrder/', '')
      
      shop.init_session
      draft_order = ShopifyAPI::DraftOrder.find(draft_order_numeric_id)

      if draft_order.complete(payment_pending: true)
        Rails.logger.info "Successfully created COD order: #{draft_order.order_id}"
        return draft_order.order_id
      else
        Rails.logger.error "Failed to complete draft order: #{draft_order_numeric_id}"
        return nil
      end
    rescue StandardError => e
      Rails.logger.error "Error completing draft order: #{e.message}"
      @complete_raised = true
      nil
    end
  end
end
