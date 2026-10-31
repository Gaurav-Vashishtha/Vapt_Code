class OrderConfirmationsController < ApiController
  include TwilioHelper
  include ShippingPublicApiOrigin
  before_action :set_shop_webhook, only: %i[]
  before_action :set_shop, only: %i[index]
  before_action :verify_webhook, only: %i[ create ]
  before_action :verify_shipping_public_api_origin!,
                only: %i[shipping_addresses]
  before_action :skip_rails_session,
                only: %i[pre_order_otp pre_order_otp_verify sso_check sso_logout
                         persistent_signin_stat]

  MAX_TRIES = 5

  # GET /order_confirmations/:id
  def show
    if params[:id]==='redirect_to_prepaid_link'
      return redirect_to_prepaid_link
    end
    if !params[:digest].blank?
      resp = prepaid2(params)
      if resp.blank?
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n  Unable to convert order to prepaid post payment - #{params}"
        )
        return
      end
      redirect_to prepaid2(params)
      return
    end
    if params[:id]==='create_prepaid_link'
      render json: {response: create_prepaid_link}
      return
    end
    order_id = params[:order_id]
    if order_id.blank? && !params[:full_url].blank?
      parsed_url =  URI.parse(URI.decode_www_form_component(params[:full_url]))
      query_hash = Rack::Utils.parse_query(parsed_url.query)
      if !query_hash['gid'].blank?
        order_id = query_hash['gid']
      end
    end
    domain = ''
    if !params[:domain].blank?
      domain = params[:domain]
    elsif !params[:shop].blank?
      # Checkout / post-purchase (e.g. sso_bridge) often sends ?shop=store.myshopify.com only
      domain = params[:shop].to_s
    elsif !params[:full_url].blank?
      domain = params[:full_url].gsub('https://','').gsub('http://','').split('/')[0]
    end
    @shop = Shop.find_by(
      shopify_domain: domain
    ) 
    if @shop.blank?
      render json: {error:'Invalid shop'}
      return
    end
    if !order_id.blank?
      @order_confirmation = OrderConfirmation.find_by(order_id: order_id)
    elsif params[:checkout_token]
      @order_confirmation = @shop.order_confirmations.where(checkout_token: params[:checkout_token]).first
    elsif params[:order_url]
      order_hash_key = params[:order_url].split('/')[-1]
      @order_confirmation = @shop.order_confirmations.where("order_status_url LIKE ?", "%#{OrderConfirmation.sanitize_sql_like(order_hash_key.to_s)}%").first
    end
    if !@order_confirmation 
      if @shop
        if ENV.fetch("SAVE_ORDER_SYNC", nil)=="true"
          render json: FetchOrderAndCreateOrderConfirmationJob.new.perform(order_id,JSON.parse(params.to_json).to_h,  @shop.id,true), except: %i[order_status_url persisted_otp shipping_address]
          return
        else
          FetchOrderAndCreateOrderConfirmationJob.perform_async(order_id,JSON.parse(params.to_json).to_h,  @shop.id,false)
        end
      else
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n  *Unable to get shop for order confirmation #{params}"
        )
      end
    end
    render json: @order_confirmation, except: %i[order_status_url persisted_otp shipping_address]
  end

  # Public redirect helper:
  # - If the order exists in `order_confirmations` and was converted to NEW_ORDER partial-payment flow,
  #   redirect to the new order's order_status_url (draft_order_id).
  # - Else redirect to the original order_status_url.
  # - If not present in DB, fetch order_status_url from Shopify and redirect.
  #
  # Params:
  # - shopify_domain (or shop/domain): e.g. "example.myshopify.com"
  # - order_id: Shopify order numeric id (string/integer)
  def public_order_status
    domain = params[:shopify_domain].presence || params[:shop].presence || params[:domain].presence
    order_id = params[:order_id].presence

    if domain.blank? || order_id.blank?
      render json: { status: "Error", message: "shopify_domain and order_id are required" }, status: :bad_request
      return
    end

    shop = Shop.find_by(shopify_domain: domain.to_s)
    if shop.blank?
      render json: { status: "Error", message: "Shop not found" }, status: :not_found
      return
    end

    order_id_str = order_id.to_s
    order_confirmation = shop.order_confirmations.find_by(order_id: order_id_str)

    url = nil

    begin
      if order_confirmation.present?
        # NEW_ORDER flow: original order_confirmation.draft_order_id points to the new order
        if order_confirmation.draft_order_id.present?
          new_order_id = order_confirmation.draft_order_id.to_s
          new_oc = shop.order_confirmations.find_by(order_id: new_order_id)
          url = new_oc&.order_status_url

          if url.blank?
            shop.init_session
            shopify_order = ShopifyAPI::Order.find(new_order_id)
            url = shopify_order&.order_status_url
            new_oc&.update(order_status_url: url) if url.present?
          end
        end

        url ||= order_confirmation.order_status_url
        if url.blank?
          shop.init_session
          shopify_order = ShopifyAPI::Order.find(order_id_str)
          url = shopify_order&.order_status_url
          order_confirmation.update(order_status_url: url) if url.present?
        end
      else
        shop.init_session
        shopify_order = ShopifyAPI::Order.find(order_id_str)
        url = shopify_order&.order_status_url
      end
    rescue => e
      SlackNotifyJob.perform_async(
        ":warning: (#{Rails.env})\npublic_order_status failed\nShop: #{domain}\nOrder: #{order_id_str}\nError: #{e.class} #{e.message}"
      )
      url = order_confirmation&.order_status_url
    end

    if url.blank?
      render json: { status: "Error", message: "Order status URL not available" }, status: :not_found
      return
    end

    redirect_to url, allow_other_host: true
  end

  def render_otp_box
    checkout_token = params[:checkout_token]
    domain = ''
    if !params[:domain].blank?
      domain = params[:domain]
    end

    orderId = ''
    if !params[:order_id].blank?
      orderId = params[:order_id]
    end

    if domain.blank? || (checkout_token.blank? && orderId.blank?)
      render json: {error:true, message:'Mandatory Params missing'}
      return
    end

    @shop = Shop.find_by(shopify_domain:domain)
    if @shop.blank?
      render json: {error:true, message:'Shop not found'}
      return
    end

    if !@shop.setting.sms
      render json: {render_otp_box: false}
      return
    end

    @order_confirmation = @shop.order_confirmations.find_by(checkout_token:checkout_token)
    if !@order_confirmation.blank? 
      render json: {render_otp_box: (@order_confirmation.is_cod_order && @order_confirmation.status == 'Pending')}
      return
    end

    if @order_confirmation.blank?
      if !orderId.blank?
        response = ShopifyServices::FastOrderByIdGetService.call(
          @shop,
          orderId
        )
        if response.blank?
          render json: {render_otp_box:"-1"} 
          return
        end
        render json: response
        return
      elsif !checkout_token.blank?    
        render_otp_box = ShopifyServices::FastOrderGetService.call(
          @shop,
          checkout_token
        )
        if render_otp_box.blank?
          render json: {render_otp_box:"-1"} 
          return
        end
        render json: {render_otp_box:render_otp_box}  
      end
      return
    end

    render json: {success:true}
  end

  def zip_details
    zip = params[:zip]
    country_code = params[:country_code]
    if zip.blank? || country_code.blank?
      render json: { response: 'Required params missing - zip & country_code' }
      return
    end

    locations = Location.where(zipcode:zip).where(country:country_code)
    if locations.count == 0 
      render json: {location:{}}  
      return
    end
    render json: {location:locations.first}  
  end

  # ✅ Enhanced partial_cart with comprehensive validation and BOGO support
  def partial_cart
    unless params['shopifyDomain'] && params['inputCart'] && params['_codkSessionId']
      render json: { response: 'Required params missing - partial_cart (shopifyDomain, inputCart, _codkSessionId)' }
      return
    end
  
    shop = Shop.find_by(shopify_domain: params['shopifyDomain'])
    if shop.nil?
      render json: { response: 'Invalid shop passed' }
      return
    end
  
    session_id = params['_codkSessionId']
    cart_rule_id = params['cartRuleId']
    cart_rule_set = nil
    
    if cart_rule_id.present?
      cart_rule_set = PartialRuleSet.find_by(id: cart_rule_id, is_cart_rule: true, shop_id: shop.id)
      if cart_rule_set.blank?
        render json: { response: 'Invalid cartRuleId' }
        return
      end
    end
  
    begin
      input_cart = params[:inputCart].map(&:to_unsafe_h)
      
    rescue => e
      render json: { response: 'Invalid inputCart format' }
      return
    end
  
    # ✅ BOGO Cost Validation - If isBOGODiscount is true but cost is not 0, set isBOGODiscount to false
    input_cart.each do |item|
      if item['isBOGODiscount'] == true && item['cost'].to_f != 0.0
        Rails.logger.info "BOGO item with non-zero cost detected. Item ID: #{item['id']}, Cost: #{item['cost']}. Setting isBOGODiscount to false."
        item['isBOGODiscount'] = false
      end
    end
  
    # ✅ Enhanced input validation for cart items
    validation_result = validate_cart_items(input_cart, cart_rule_id, shop)
    unless validation_result[:valid]
      render json: { 
        response: validation_result[:error],
        validation_errors: validation_result[:details]
      }
      return
    end
  
    # ✅ BOGO HANDLING - Check if cart contains only BOGO items
    bogo_items = input_cart.select { |item| item['isBOGODiscount'] == true }
    
    if bogo_items.any?
      # Handle mixed cart (BOGO + regular items)
      if bogo_items.length < input_cart.length
        Rails.logger.info "Mixed cart detected: #{bogo_items.length} BOGO items, #{input_cart.length - bogo_items.length} regular items"
        response_cart = handle_mixed_bogo_cart(shop, input_cart, session_id, cart_rule_id, cart_rule_set)
      else
        Rails.logger.info "Pure BOGO cart detected: all #{bogo_items.length} items are BOGO discounts"
        response_cart = handle_pure_bogo_cart(input_cart)
      end
      
      render json: { response: response_cart }
      return
    end
  
    # ✅ FIXED: Calculate cart_hash ONCE at request start and propagate everywhere
    cart_hash = PartialCartService.generate_cart_hash(input_cart)
    Rails.logger.info "📦 Generated cart_hash for request: #{cart_hash&.first(16)}... (calculated once at request start)"
    
    # Try to use pre-created mappings first with enhanced validation (for non-BOGO items)
    if shop.setting&.partial_payment_enabled?
      # Wait briefly for pre-creation to complete if in progress
      max_wait_time = 5.seconds
      start_time = Time.current
      
      while Time.current - start_time < max_wait_time
        cached_response = try_cached_partial_cart(shop, input_cart, session_id, cart_rule_id, cart_hash)
        if cached_response
          render json: { response: cached_response }
          return
        end
        
        # Check if pre-creation is still running (use same cart_hash)
        cache_key = "pre_create_lock_#{shop.id}_#{cart_hash}_#{session_id}"
        break unless Rails.cache.exist?(cache_key)
        
        sleep(0.5) # Wait 500ms before retry
      end
    end
  
    # Fallback to original logic for non-BOGO items (pass cart_hash)
    fallback_partial_cart_creation(shop, input_cart, cart_rule_set, cart_rule_id, session_id, cart_hash)
  rescue => e
    render json: { response: "An error occurred: #{e.message}" }
  end
  
  def update_cart_details
    required_params = %i[device_id shop cart_details]
  
    if required_params.any? { |key| params[key].blank? }
      return render json: { error: "Missing required parameters" }, status: :bad_request
    end
  
    unless params[:cart_details].is_a?(Array)
      return render json: { error: "cart_details should be an array" }, status: :unprocessable_entity
    end
  
    # Find the shop for pre-creation
    shop = Shop.find_by(shopify_domain: params[:shop])
    if shop.nil?
      return render json: { error: "Invalid shop domain" }, status: :not_found
    end
  
    # CONVERT ACTIONCONTROLLER::PARAMETERS TO REGULAR HASHES
    permitted_cart_details = params[:cart_details].map do |item|
      item.permit(
        :product_id, :productId, :variant_id, :title, :quantity, :price, :featured_image,
        :cost, :totalQuantity, :qty, :imageUrl, :image_url, :variantId
      ).to_h
    end
  
    # Check if cart contains any partial payment products
    has_partial_payment_products = permitted_cart_details.any? do |item|
      title = item['title'] || item[:title] || ''
      title.start_with?('Partial Payment for')
    end
  
    if has_partial_payment_products
      Rails.logger.info "Skipping pre-creation and save logic - cart contains partial payment products"
      
      return render json: { 
        message: "Cart details processed successfully", 
        note: "Skipped pre-creation and save logic as cart contains partial payment products",
        pre_creation_triggered: false,
        device_id: params[:device_id],
        has_partial_payment_products: true
      }, status: :ok
    end
  
    # Pre-create partial products if enabled and partial_payment_flow_version is 1 (only for non-partial payment products)
    if shop.setting&.partial_payment_enabled? && shop.setting&.partial_payment_flow_version == 1
      begin
        # Use device_id as session_id for tracking
        session_id = params[:device_id]
        
        Rails.logger.info "Triggering pre-creation for #{permitted_cart_details.count} non-partial payment items"
        
        # Pre-create partial products asynchronously - NOW WITH PERMITTED DATA
        PartialCartService.pre_create_partial_products(shop, permitted_cart_details, session_id)
      rescue => e
        # Log error but don't fail the cart update
        Rails.logger.error "Pre-creation error: #{e.message}"
      end
    end
  
    # Persistent sign-in / SSO sessions skip the OTP send, so this device has no row yet. Create a
    # non-billable one (proved by the signed sso_session_token) so the cart is tracked for
    # abandonment, reminders and draft orders like any other pre-order OTP session.
    if params[:sso_session_token].present?
      PreOrderOtp.ensure_for_persistent_signin(
        shop,
        device_id: params[:device_id],
        sso_token: params[:sso_session_token],
        cart_details: permitted_cart_details
      )
    end

    # Find all pre_order_otps for this device_id (only for non-partial payment products)
    pre_order_otps = PreOrderOtp.where(device_id: params[:device_id])
    
    if pre_order_otps.exists?
      updated_records = []
      failed_records = []
      
      # Update all matching records - USE PERMITTED DATA
      pre_order_otps.each do |pre_order_otp|
        if pre_order_otp.update(cart_details: permitted_cart_details, order_status: 'IN_PROGRESS')
          updated_records << pre_order_otp
        else
          failed_records << {
            id: pre_order_otp.id,
            errors: pre_order_otp.errors.full_messages
          }
        end
      end
      
      if failed_records.empty?
        # All records updated successfully
        render json: { 
          message: "Cart details updated successfully for all records", 
          updated_count: updated_records.count,
          data: updated_records,
          pre_creation_triggered: shop.setting&.partial_payment_enabled? || false,
          has_partial_payment_products: false
        }, status: :ok
      else
        # Some records failed to update
        render json: { 
          message: "Cart details partially updated", 
          updated_count: updated_records.count,
          failed_count: failed_records.count,
          updated_data: updated_records,
          failed_records: failed_records,
          pre_creation_triggered: shop.setting&.partial_payment_enabled? || false,
          has_partial_payment_products: false
        }, status: :partial_content
      end
    else
      # No pre_order_otp found, but that's okay
      # Pre-creation has already been triggered above
      render json: { 
        message: "Cart details processed successfully", 
        note: "No existing order records found for device_id, but partial products pre-creation triggered",
        pre_creation_triggered: shop.setting&.partial_payment_enabled? || false,
        device_id: params[:device_id],
        has_partial_payment_products: false
      }, status: :ok
    end
  rescue => e
    render json: { error: "Internal Server Error", details: e.message }, status: :internal_server_error
  end

  def partial_rule_sets
    shop = Shop.find_by(shopify_domain: params['shopifyDomain'])
    if shop.blank?
      render json: { response: 'Invalid shop passed' }
      return
    end

    # 5 min refresh: if rule-set metafield was last synced > 5 min ago (or never), enqueue job to refresh metafields
    # if shop.respond_to?(:partial_rule_sets_metafield_synced_at)
    #   synced_at = shop.partial_rule_sets_metafield_synced_at
    #   if synced_at.blank? || synced_at < 5.minutes.ago
    #     ShopifyJobs::RefreshPartialRuleSetsMetafieldJob.perform_later(shop.id)
    #   end
    # end

    

    #ShopifyJobs::PartialDiscountAutomaticAppJob.perform_async(shop.id) if should_enqueue_partial_discount_job
   

    render json: { rule_sets: PartialRuleSet.find_rule_sets_by_product_and_shop(shop, params['productId']) }
  end

  def partial_dummy_variant_id
    shop = Shop.find_by(shopify_domain: params['shopifyDomain'])
    if shop.blank?
      render json: {error: 'Invalid shop passed'}, status: :bad_request
      return
    end

    setting = shop.setting
    if setting.blank? || setting.partial_payment_enabled == false
      render json: {error: 'Setting not found for shop or partial payment is disabled'}, status: :not_found
      return
    end

    # Check if variant ID already exists in settings
    if setting.partial_dummy_variant_id.present?
      # Verify the variant actually exists in Shopify
      if variant_exists_in_shopify?(shop, setting.partial_dummy_variant_id)
        render json: {variant_id: setting.partial_dummy_variant_id}
        return
      else
        # Variant doesn't exist in Shopify, clear it from settings and create a new one
        puts "⚠️ Variant ID #{setting.partial_dummy_variant_id} not found in Shopify, creating new one..."
        setting.update(partial_dummy_variant_id: nil)
      end
    end

    # Create the dummy variant if it doesn't exist
    begin
      variant_id = ShopifyServices::PartialDummyVariantCreateService.call(shop)
      
      # Store the variant ID in settings
      setting.update(partial_dummy_variant_id: variant_id)
      #ShopifyJobs::PartialDiscountAutomaticAppJob.perform_async(shop.id)
      
      render json: {variant_id: variant_id}
    rescue => e
      puts "❌ Error creating partial dummy variant: #{e.message}"
      render json: {error: "Failed to create dummy variant: #{e.message}"}, status: :internal_server_error
    end
  end

  def is_cod_king_block_enabled
    begin
      
      shop = Shop.find_by(shopify_domain:params['shopifyDomain'])
      if shop.blank?
        render json: { errror: 'Invalid shopifyDomain' }  
      end
      if Rails.env.development?
        response = true
      else
        response = ShopifyServices::ShopifyAssetService.new(shop).is_cod_king_block_enabled?
      end
      render json: { assetEnabled: response }
    rescue => e
      render json: { error: "Failed to fetch COD King block status", message: e.message }, status: :internal_server_error
    end
  end

  # Queue the partial-order edit for one order, the same way
  # OrderConfirmationCreateJob does once it has classified an order as partial.
  # Unlike trigger_order_confirmation this skips the classification step and
  # goes straight to the edit, so it re-runs the flatten on an order whose
  # OrderConfirmation already exists.
  #
  #   GET /order_confirmations/trigger_partial_order_edit?shop_id=2&order_id=123
  #
  # retry=true routes to BundleTwoCommit instead of Bundle.
  def trigger_partial_order_edit
    shop_id = params[:shop_id]
    order_id = params[:order_id]

    if shop_id.blank? || order_id.blank?
      render json: { error: 'Missing required parameters: shop_id and order_id' }, status: :bad_request
      return
    end

    shop = Shop.find_by(id: shop_id)
    if shop.blank?
      render json: { error: 'Shop not found' }, status: :not_found
      return
    end

    if shop.setting.blank?
      render json: { error: 'Shop has no settings record' }, status: :unprocessable_entity
      return
    end

    order_confirmation = OrderConfirmation.find_by(shop_id: shop.id, order_id: order_id)
    if order_confirmation.blank?
      render json: {
        error: 'No OrderConfirmation for that shop and order',
        hint: 'Run trigger_order_confirmation first — it creates the record and enqueues this job itself when the order is partial.'
      }, status: :not_found
      return
    end

    retry_flag = ActiveModel::Type::Boolean.new.cast(params[:retry]).present?

    # partial_variant_ids is passed as nil: the job falls back to
    # order_confirmation.partial_payment_variants, which is where the webhook
    # path stored them.
    ShopifyJobs::PartialOrderEditJob.perform_async(shop.id, order_id, nil, retry_flag)

    Rails.logger.info(
      "[Codk::PartialPayment] trigger_partial_order_edit queued PartialOrderEditJob " \
      "shop_id=#{shop.id} order_id=#{order_id} retry=#{retry_flag}"
    )

    render json: {
      success: true,
      message: 'Partial order edit job queued successfully',
      shop_id: shop.id,
      order_id: order_id,
      retry: retry_flag,
      status_before: order_confirmation.status
    }
  end

  def trigger_order_confirmation
    shop_id = params[:shop_id]
    order_id = params[:order_id]

    if shop_id.blank? || order_id.blank?
      render json: { error: 'Missing required parameters: shop_id and order_id' }, status: :bad_request
      return
    end

    begin
      shop = Shop.find(shop_id)
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Shop not found' }, status: :not_found
      return
    end

    begin
      shop.init_session
      shopify_order = ShopifyAPI::Order.find(order_id)
      
      if shopify_order.blank?
        render json: { error: 'Shopify order not found' }, status: :not_found
        return
      end

      payload = JSON.parse(shopify_order.to_json).to_h
      Rails.logger.info(
        "[Codk::PartialPayment] trigger_order_confirmation queued OrderConfirmationCreateJob shop_id=#{shop.id} order_id=#{order_id}"
      )
      OrderConfirmationCreateJob.perform_async(payload, shop.id)
      render json: { 
        success: true, 
        message: 'Order confirmation job queued successfully',
        shop_id: shop.id,
        order_id: order_id
      }
    rescue => e
      render json: { 
        error: 'Failed to process order', 
        message: e.message 
      }, status: :internal_server_error
    end
  end

  

  def variant_exists_in_shopify?(shop, variant_id)
    return false if variant_id.blank?

    begin
      # Create a temporary service instance to get the GraphQL client
      service = ShopifyServices::PartialDummyVariantCreateService.new(shop)
      client = service.instance_variable_get(:@client)
      return false unless client

      # Convert numeric ID to GraphQL ID format if needed
      gql_variant_id = variant_id.to_s.start_with?('gid://') ? variant_id : "gid://shopify/ProductVariant/#{variant_id}"

      # Query to check if variant exists
      query = client.parse <<-'GRAPHQL'
        query($id: ID!) {
          productVariant(id: $id) {
            id
            title
            product {
              id
              status
            }
          }
        }
      GRAPHQL

      variables = { id: gql_variant_id }
      response = client.query(query, variables: variables).to_h

      # Check for errors
      if response["errors"]&.any?
        error_msg = response["errors"].map { |e| e["message"] }.join(", ")
        puts "⚠️ GraphQL errors checking variant existence: #{error_msg}"
        return false
      end

      # Check if variant was found
      variant = response.dig("data", "productVariant")
      return false if variant.blank?
      product_status = variant.dig("product", "status")
      if product_status != "ACTIVE"
        puts "⚠️ Variant #{variant_id} exists but product is not active (status: #{product_status})"
        return false
      end

      puts "✅ Variant #{variant_id} exists in Shopify and product is active"
      true
    rescue => e
      puts "⚠️ Error checking variant existence: #{e.message}"
      # If there's an error checking, assume it doesn't exist to be safe
      # SlackNotifyJob.perform_async(
      #   ":rage:  (#{Rails.env})\n  *Error querying variant existence* Variant #{variant_id} found in Shopify #{shop.shopify_domain}"
      # )
      return true
    end
  end

  # POST /order_confirmations or /order_confirmations.json
  def create
    NetworkJobs::WebhookForwarderJob.perform_async(JSON.parse(params.to_json).to_h,request.headers['X-Shopify-Shop-Domain'],'create')
    render json: { success: true }
  end

  def order_fulfilled
    NetworkJobs::WebhookForwarderJob.perform_async(JSON.parse(params.to_json).to_h,request.headers['X-Shopify-Shop-Domain'],'fulfiled')
    render json: { success: true }
  end

  def create_order
    OrderConfirmationCreateJob.perform_async(JSON.parse(params.to_json).to_h, @shop.id)
    render json: { success: true }
  end

  def confirm_order_manually
    puts "confirm_order_manually  #{params}"
    @order_confirmation = OrderConfirmation.find_by(
      order_id: params[:orderId]
    )
    if @order_confirmation.update(status:'COD-Manual-Verified')
      ShopifyJobs::OrderPostJob.perform_async(@order_confirmation.shop.id, @order_confirmation.id)
      # BSP order_created when bound, else MSG91 confirmation — one place decides.
      Whatsapp::OrderConfirmationNotifier.call(shop: @order_confirmation.shop, order_confirmation: @order_confirmation)
    end
    if @order_confirmation
        render json: @order_confirmation
    else
        render json: @order_confirmation.errors, status: :unprocessable_entity
    end
  end

  def resend_message
    puts "resend_message  #{params}"
    resp = NetworkServices::ResendOtpService.call(params[:orderId])
    if resp
      render json: @order_confirmation
    else
      render json: 'Error in sending message, check max limit', status: :unprocessable_entity
    end
  end

  def shipping_address_count
    shop = Shop.find_by(shopify_domain: params["shopifyDomain"])
    if shop.blank?
      render json: { error: true, message: "Invalid Shop" }
      return
    end

    phone = normalize_public_shipping_phone_param
    if phone.blank?
      render json: { error: true, message: "phone is required" }, status: :bad_request
      return
    end

    shipping_data = Customer.fetch_shipping_address_by_phone(phone, track_stat: false)
    customer = Customer.find_by(phone: phone)
    email = Customer.real_email(customer&.email) || ""

    if shipping_data.blank?
      render json: { shippingAddressCount: 0, email: email }
    else
      render json: { shippingAddressCount: shipping_data.count, email: email }
    end
  end

  # Address list only (max 10, dedupe, cache). For count alone use shipping_address_count.
  def shipping_addresses
    shop = Shop.find_by(shopify_domain: params["shopifyDomain"])
    if shop.blank?
      render json: { error: true, message: "Invalid Shop" }
      return
    end

    phone = normalize_public_shipping_phone_param
    if phone.blank?
      render json: { error: true, message: "phone is required" }, status: :bad_request
      return
    end

    shipping_data = Customer.fetch_shipping_address_by_phone(phone)
    customer = Customer.find_by(phone: phone)
    email = Customer.real_email(customer&.email) || ""
    list = shipping_data.is_a?(Array) ? shipping_data : []

    render json: {
      shipping_addresses: list,
      email: email
    }
  end

  def country_codes
    country_codes = TwilioPricing.distinct.pluck(:country_code, :country).map do |code, name|
      { country_code: code, country: name }
    end

    render json: { country_codes: country_codes }, status: :ok
  end

  def pricing
    record = TwilioPricing.find_by(country_code: params[:country_code])

    if record
      shop = pricing_shop_for_sms_rate
      sms_price = PhilippinesSmsRate.effective_sms_base_usd(
        country_code: record.country_code,
        shop_id: shop&.id,
        db_sms_price: record.sms_price.to_f
      )
      render json: {
        country: record.country,
        country_code: record.country_code,
        sms_price: sms_price,
        whatsapp_price: record.whatsapp,
        # nil when the category column is unset, so the page falls back to whatsapp_price
        # exactly as MessagePricing does when billing.
        whatsapp_utility_price: record.whatsapp_utility.to_f.positive? ? record.whatsapp_utility.to_f : nil,
        whatsapp_marketing_price: record.whatsapp_marketing.to_f.positive? ? record.whatsapp_marketing.to_f : nil,
        bsp_whatsapp_price: MessagePricing::BSP_WHATSAPP_USD,
        # Percent fee per partially paid order, per plan, from the same source billing uses,
        # so the plan cards can't drift from what the merchant is charged.
        partial_payment_rates: partial_payment_rates_percent(shop),
        pricing_version: india_v3_pricing?(record, shop) ? "v3" : "v2",
        v3_rates_inr: india_v3_pricing?(record, shop) ? PricingV3India::RATES_INR : nil,
        subscription_offer: {
          active: SubscriptionOffer.eligible?(shop),
          charge_display: SubscriptionOffer.charge_display
        },
        # Running country offers for this shop, by plan name: {"Enterprise" => {"trial_days" => 90, ...}}
        country_offers: CountryPlanOffer.display_for(shop)
      }, status: :ok
    else
      render json: { error: 'Country code not found' }, status: :not_found
    end
  end

  def create_discount_code
    render json: { success: true}
  end

  def send_locked_capped_email
    shop = Shop.find(params[:shop_id])
    job = WelcomeMailer.lock_shop_capped_amount_exceeded(shop.id).deliver_later
    render json: { message: job}
  end

  def pre_order_otp
    @shop = Shop.find_by(
      shopify_domain: params['shop']
    )
    puts "pre_order_otp call  #{params}"
    if @shop.blank?
      render json: { status: 'Error', Notes: 'Shop not found' }, status: :not_found
      return
    end

    payload = NetworkServices::SendPreOrderOtpService.call(@shop.id, params)
    if payload.nil?
      payload = {
        status: 'Error',
        Notes: 'Unable to send OTP. Please try again.',
        code: 'pre_order_otp_empty_response'
      }
    end
    status = if payload.is_a?(Hash) && (payload[:code] == 'checkout_otp_plan_forbidden' || payload['code'] == 'checkout_otp_plan_forbidden')
      :forbidden
    else
      :ok
    end
    render json: payload, status: status
  end

  def pre_order_otp_verify
    @shop = Shop.find_by(
      shopify_domain: params['shop']
    )
    puts "pre_order_otp_verify call  #{params}"
    if @shop.blank?
      render json: { verification: false, status: 'error', Notes: 'Shop not found' }, status: :not_found
      return
    end

    payload = NetworkServices::VerifyPreOrderOtpService.call(@shop.id, params)
    code = payload.is_a?(Hash) ? (payload[:code] || payload["code"]) : nil
    status = code == "checkout_otp_plan_forbidden" ? :forbidden : :ok

    if payload.is_a?(Hash) && payload["sso_session_token"].present?
      cookies[:codk_sso] = {
        value: payload["sso_session_token"],
        path: "/",
        max_age: 30.days.to_i,
        httponly: true,
        secure: true,
        same_site: :none
      }
      Rails.logger.info "[SSO] codk_sso cookie set for token: #{payload['sso_session_token']}"
    end

    render json: payload, status: status
  end

  def sso_check
    token = cookies[:codk_sso] || request.headers['X-SSO-Token'] || params[:sso_token]
    Rails.logger.info "[SSO] sso_check called, token present: #{token.present?}"

    if token.blank?
      Rails.logger.info "[SSO] No codk_sso cookie found"
      render json: { valid: false, reason: 'no_token' } and return
    end

    payload =
      begin
        SsoJwtService.decode(token)
      rescue SsoJwtService::MissingSecretError => e
        Rails.logger.error "[SSO] #{e.message}"
        render json: { valid: false, reason: 'server_misconfigured' }, status: :internal_server_error and return
      end

    if payload.nil?
      Rails.logger.info "[SSO] JWT invalid or expired"
      cookies.delete(:codk_sso, path: '/', secure: true, httponly: true, same_site: :none)
      render json: { valid: false, reason: 'expired_or_invalid' } and return
    end

    phone = payload[:phone]
    country_code = payload[:country_code]
    Rails.logger.info "[SSO] Valid JWT for phone: #{phone}"

    @shop = Shop.find_by(shopify_domain: params['shop'])
    result = { valid: true, phone: phone, country_code: country_code, verification: true, sso_session_token: token }

    if @shop.present?
      Rails.logger.info "[SSO] Shop found: #{@shop.shopify_domain}, checking shipping addresses"
      if @shop.setting&.is_prefilled_address_enabled || @shop.setting&.cod_form_enabled
        shipping_data = Customer.fetch_shipping_address_by_phone(phone)
        result[:shippingAddress] = shipping_data if shipping_data.present?
        Rails.logger.info "[SSO] Shipping addresses found: #{shipping_data&.count || 0}"
      end

      if @shop.setting&.pre_is_login_enabled
        customer_login = CustomerLogin.find_by(phone: phone, shopify_domain: @shop.shopify_domain)
        result[:customerLogin] = customer_login || {}
        Rails.logger.info "[SSO] Customer login lookup done"
      end
    else
      Rails.logger.warn "[SSO] Shop not found for domain: #{params['shop']}"
    end

    render json: result
  end

  def sso_logout
    Rails.logger.info "[SSO] sso_logout called, cookie present: #{cookies[:codk_sso].present?}"
    cookies.delete(:codk_sso, path: '/', secure: true, httponly: true, same_site: :none)
    Rails.logger.info "[SSO] codk_sso cookie deletion sent in response"
    render json: { success: true }
  end

  def persistent_signin_stat
    head :no_content and return unless PersistentSigninTally.enabled?

    hit = cookies[:codk_sso].present?

    begin
      StatsJobs::PersistentSigninTallyJob.perform_async(hit)
    rescue => e
      Rails.logger.warn "[PersistentSignin] tally enqueue failed: #{e.message}"
    end

    render json: { sso: hit ? 'HIT' : 'MISS' }
  end

  def config_metafields
    @shop = Shop.find_by(
      id: params['shop_id']
    )
    if @shop.blank?
      render json: {message: "No Shop found with supplied id:#{params['shop_id']}"}  
      return
    end

    payment_raw = ShopifyServices::PaymentFunctionMetafieldReaderService.call(@shop, @shop.setting.payment_customization_id)
    delivery_raw = ShopifyServices::DeliveryFunctionMetafieldReaderService.call(@shop, @shop.setting.delivery_customization_id)

    payment_config = payment_raw.is_a?(String) ? JSON.parse(payment_raw) : payment_raw
    delivery_config = delivery_raw.is_a?(String) ? JSON.parse(delivery_raw) : delivery_raw

    render json: {
      payment_function_config: payment_config,
      delivery_function_config: delivery_config
    }
  end

  def initiate_s3_backup
    if params['clientToken']!=ENV.fetch("EASY_SELL_AUTH_TOKEN", nil)
      render json: {status: 'Error', message:'Unauthorized access'}
      return  
    end

    s3_url = params['s3Url']
    job_id = NetworkJobs::AwsDumpCopyJob.perform_async(s3_url)    

    render json: {success: "Initiated #{job_id}"}
  end 

  def review_whatsapp
    if params['clientToken']!=ENV.fetch("EASY_SELL_AUTH_TOKEN", nil)
      render json: {status: 'Error', message:'Unauthorized access'}
      return  
    end

    @shop = Shop.find_by(
      shopify_domain: params['shopifyDomain']
    )
    if @shop.blank?
      render json: {message: "No Shop found with supplied shopifyDomain:#{params['shopifyDomain']}"}  
      return
    end
    puts " review_whatsapp call #{params}"
    @shop.setting.update(whatsapp_approval_status: params['approvalStatus'])
    render json: {approvalStatus: @shop.setting.whatsapp_approval_status}
  end 

  def pending_whatsapp
    if params['clientToken']!=ENV.fetch("EASY_SELL_AUTH_TOKEN", nil)
      render json: {status: 'Error', message:'Unauthorized access'}
      return  
    end
    response = []
    settings = Setting.where(whatsapp_approval_status: 'requested')
    if settings.count > 0
      settings.each do |setting| 
        response.push(setting.shop.shopify_domain)
      end
    end
    render json: {approvalStatus: response}
  end 

  def refresh_payment_customization
    if params['clientToken']!=ENV.fetch("EASY_SELL_AUTH_TOKEN", nil)
      render json: {status: 'Error', message:'Unauthorized access'}
      return  
    end

    @shop = Shop.find_by(
      id: params['shop_id']
    )
    if @shop.blank?
      render json: {message: "No Shop found with supplied id:#{params['shop_id']}"}  
      return
    end
    puts " refresh_payment_customization call  #{params}"
    payment_id = ShopifyServices::PaymentCustomizationService.call(@shop , '')
    delivery_id = ShopifyServices::DeliveryCustomizationService.call(@shop)
    ShopifyServices::PartialDiscountAutomaticAppEnsureService.call(@shop.id)
    render json: {id: [payment_id,delivery_id]}
  end 



  def restart_web_dynos
    if params['clientToken']==ENV.fetch("EASY_SELL_AUTH_TOKEN", nil)
      SidekiqJobs::RestartAppJob.perform_later
      render text: 'Restart triggered'
    else
      render text: 'You are not allowed to restart the dynos'
    end
  end

  def easysell_send_otp
    puts "easysell_send_otp call  #{params}"
    if params['phone'].blank? || params['store'].blank?  || params['countryCode'].blank?  || params['otp'].blank? || params['clientToken'].blank?
      render json: {status: 'Error', message:'Mandatory params are missing'}
      return  
    end

    if params['clientToken']!=ENV.fetch("EASY_SELL_AUTH_TOKEN", nil)
      render json: {status: 'Error', message:'Unauthorized access'}
      return  
    end

    NetworkJobs::EasysellSendSmsJob.perform_async(params['phone'],params['store'],params['countryCode'],params['otp'])
    render json: {status: 'Submitted'}
  end 

  def easysell_send_confirmation_sms
    puts "easysell_send_confirmation call  #{params}"
    if params['phone'].blank? || params['store'].blank?  || params['countryCode'].blank?  || params['clientToken'].blank?
      render json: {status: 'Error', message:'Mandatory params are missing'}
      return  
    end

    if params['clientToken']!=ENV.fetch("EASY_SELL_AUTH_TOKEN", nil)
      render json: {status: 'Error', message:'Unauthorized access'}
      return  
    end
    NetworkJobs::EasysellSendConfirmationSmsJob.perform_async(params['phone'],params['store'],params['countryCode'],params['orderNumber'],params['orderUrl'])
    render json: {status: 'Submitted'}
  end

  def easysell_send_fulfiment_sms
    puts "easysell_send_fulfilment_sms call  #{params}"
    if params['phone'].blank? || params['store'].blank?  || params['countryCode'].blank?  || params['clientToken'].blank? || params['trackingUrl'].blank?
      render json: {status: 'Error', message:'Mandatory params are missing'}
      return  
    end

    if params['clientToken']!=ENV.fetch("EASY_SELL_AUTH_TOKEN", nil)
      render json: {status: 'Error', message:'Unauthorized access'}
      return  
    end
    NetworkJobs::EasysellSendFulfilmentSmsJob.perform_async(params['phone'],params['store'],params['countryCode'],params['trackingUrl'])
    render json: {status: 'Submitted'}
  end

  def easysell_send_ac_sms
    puts "easysell_send_ac call  #{params}"
    if params['phone'].blank? || params['store'].blank?  || params['countryCode'].blank?  || params['url'].blank?   || params['clientToken'].blank?
      render json: {status: 'Error', message:'Mandatory params are missing'}
      return  
    end

    if params['clientToken']!=ENV.fetch("EASY_SELL_AUTH_TOKEN", nil)
      render json: {status: 'Error', message:'Unauthorized access'}
      return  
    end

    NetworkJobs::EasysellSendAcSmsJob.perform_async(params['phone'],params['store'],params['countryCode'],params['url'])
    render json: {status: 'Submitted'}
  end

  def confirm
    puts "confirm call  #{params}"
    @order_confirmation = OrderConfirmation.find_by(
      order_id: params[:order_id],
      persisted_otp: params[:otp]
    )
    if !@order_confirmation.blank? && @order_confirmation.status!='COD-Auto-Cancelled' && @order_confirmation.status!='COD-Cancelled' && @order_confirmation.status!='COD-Auto-Deleted'
      # Check if it's a test order
      is_test_order = @order_confirmation.order_id == '8888888888' || 
                      @order_confirmation.order_id == '1234567890' || 
                      @order_confirmation.order_id == '9999999999' || 
                      @order_confirmation.status == 'Test-Order'
      
      if @order_confirmation.update(status: 'COD-Verified', confirmed_at: Time.new, is_otp_verified: true)
        unless is_test_order
          CodFormCustomerSyncJob.perform_async(
            @order_confirmation.shop_id,
            @order_confirmation.customer_number,
            @order_confirmation.customer_email,
            @order_confirmation.customer_name
          )
          # Let OrderPostJob resolve the configured verification tag (setting.verification_tag).
          ShopifyJobs::OrderPostJob.perform_async(@order_confirmation.shop.id, @order_confirmation.id)
          # BSP order_created when bound, else MSG91 confirmation — one place decides.
          Whatsapp::OrderConfirmationNotifier.call(shop: @order_confirmation.shop, order_confirmation: @order_confirmation)
        end
        render json: @order_confirmation.as_json.merge(is_test_order: is_test_order)
      else
        render json: @order_confirmation.errors, status: :unprocessable_entity
      end
    else
      render json: { error: 'Invalid OTP or order is already cancelled, consider placing the order again. Thanks.' }, status: :unprocessable_entity
    end
  end

  def redirect_payment_link
    @shop = Shop.find_by(shopify_domain: params[:domain])
    if !@shop.blank? && @shop.setting.prepaid_enabled==true
      @order_confirmation = OrderConfirmation.find(params[:id])
      if !@order_confirmation.blank?
        if @shop.setting.payment_provider=='PHONEPE'
          redirect_to NetworkServices::PhonepeLinkService.call(@shop,@order_confirmation) 
        elsif !@order_confirmation.blank? && @shop.setting.payment_provider=='PAYMOB'
          redirect_to NetworkServices::PaymobLinkService.call(@shop,@order_confirmation)  
          return
        elsif !@order_confirmation.blank? && @shop.setting.payment_provider=='GE_IDEA'
          redirect_to NetworkServices::GeideaLinkService.call(@shop,@order_confirmation)  
          return     
        elsif !@order_confirmation.blank? && @shop.setting.payment_provider=='PAYU'
          redirect_to NetworkServices::PayuLinkService.call(@shop,@order_confirmation)
          return
        elsif !@order_confirmation.blank? && @shop.setting.payment_provider=='CASHFREE'
          redirect_to NetworkServices::CashfreeLinkService.call(@shop,@order_confirmation)
          return
        else
          redirect_to NetworkServices::RazorpayLinkService.call(@shop,@order_confirmation)
        end
      end
    end
  end

  def crisp_url
    id = params[:shop_id]
    shop =  Shop.find_by(id: id)
    
   # render json: {message: 'Non COD order' }
    render json: {response: shop.crisp_url}
  end

  def redirect_to_prepaid_link
    @order_confirmation = OrderConfirmation.find_by(digest: params[:digest])
    @shop = @order_confirmation.shop
    return unless @order_confirmation
  
    case @shop.setting.payment_provider
    when 'PHONEPE'
      redirect_to NetworkServices::PhonepeLinkService.call(@shop, @order_confirmation)
    when 'PAYMOB'
      redirect_to NetworkServices::PaymobLinkService.call(@shop, @order_confirmation)
    when 'GE_IDEA'
      redirect_to NetworkServices::GeideaLinkService.call(@shop, @order_confirmation)
    when 'PAYU'
      redirect_to NetworkServices::PayuLinkService.call(@shop, @order_confirmation)
    when 'CASHFREE'
      redirect_to NetworkServices::CashfreeLinkService.call(@shop, @order_confirmation)
    else
      if @order_confirmation.prepaid_link.blank?
        redirect_to NetworkServices::RazorpayLinkService.call(@shop, @order_confirmation)
      else
        redirect_to @order_confirmation.prepaid_link
      end
    end
  end

  def create_prepaid_link
    @shop = Shop.find_by(
      shopify_domain: params[:domain]
    )
    if params[:order_id]
      @order_confirmation = OrderConfirmation.find_by(order_id: params[:order_id])
    end

    if params[:checkout_token]
      @order_confirmation = OrderConfirmation.find_by(checkout_token: params[:checkout_token])
    end

    if @order_confirmation.blank?
      return
    end

    if !@order_confirmation.is_cod_order
      render json: {message: 'Non COD order' }
      return
    end

    if !@order_confirmation.blank? && @shop.setting.payment_provider=='PHONEPE'
      prepaid_link = NetworkServices::PhonepeLinkService.call(@shop,@order_confirmation)  
      render json: {response: prepaid_link}
      return
    end
    if !@order_confirmation.blank? && @shop.setting.payment_provider=='PAYMOB'
      prepaid_link = NetworkServices::PaymobLinkService.call(@shop,@order_confirmation)  
      render json: {response: prepaid_link}
      return
    end
    if !@order_confirmation.blank? && @shop.setting.payment_provider=='GE_IDEA'
      prepaid_link = NetworkServices::GeideaLinkService.call(@shop,@order_confirmation)  
      render json: {response: prepaid_link}
      return
    end
    if !@order_confirmation.blank? && @shop.setting.payment_provider=='PAYU'
      prepaid_link = NetworkServices::PayuLinkService.call(@shop,@order_confirmation)
      render json: {response: prepaid_link}
      return
    end
    if !@order_confirmation.blank? && @shop.setting.payment_provider=='CASHFREE'
      prepaid_link = NetworkServices::CashfreeLinkService.call(@shop,@order_confirmation)
      render json: {response: prepaid_link}
      return
    end

    if @order_confirmation.prepaid_link.blank?
        prepaid_link = NetworkServices::RazorpayLinkService.call(@shop,@order_confirmation)
        render json: {response: prepaid_link}
        return
    else
        render json: {response: @order_confirmation.prepaid_link}
        return
    end
  end

  def cancel
    puts "cancel call  #{params}"
    @order_confirmation = OrderConfirmation.find_by(
      order_id: params[:order_id],
      persisted_otp: params[:otp]
    )
    if @order_confirmation
      if @order_confirmation.update(status: 'COD-Cancelled', confirmed_at: Time.new)
        ShopifyJobs::OrderPostJob.perform_async(
          @order_confirmation.shop.id,
          @order_confirmation.id
        )
        @order_confirmation.shop.init_session
        order = ShopifyAPI::Order.find(@order_confirmation.order_id)
        if order.fulfillment_status=='restocked' 
          order.cancel(email:true, reason:'declined')
        else
          order.cancel(email:true, reason:'declined', restock:true )
        end
        
        render json: @order_confirmation
      else
        render json: @order_confirmation.errors, status: :unprocessable_entity
      end
    else
      render json: { error: I18n.t('script.invalid_otp') }, status: :unprocessable_entity
    end
  end

  def update_ph_and_send_otp
    puts "update_ph_and_send_otp #{params}"
    if params[:customer_number].blank? || params[:customer_number].length < 8
      render json: 'Invalid Phone number - Length should be more than 8 characters', status: :unprocessable_entity
      return
    end
    @order_confirmation = OrderConfirmation.find_by(
      order_id: params[:order_id]
    )
    unless @order_confirmation
      render json: { error: "Order confirmation not found" }, status: :not_found
      return
    end

    @shop = @order_confirmation.shop
    country_code = @order_confirmation.country_code.to_s.strip
    if country_code.blank?
      render json: { error: "Missing country_code for order confirmation" }, status: :unprocessable_entity
      return
    end

    phone_number = clean_phone_number(params[:customer_number], country_code.downcase)
    if @order_confirmation.update(customer_number: phone_number)
      call_sms_twillio(@order_confirmation)
      ShopifyJobs::TagAddJob.perform_async(@order_confirmation.id, '⚠ COD-NUMBER-UPDATED')
      render json: @order_confirmation
    else
      render json: @order_confirmation.errors, status: :unprocessable_entity
    end
  end

  def send_code_on_whatsapp
    puts "send_code_on_whatsapp #{params}"
    @order_confirmation = OrderConfirmation.find_by(
      order_id: params[:order_id]
    )
    @shop = @order_confirmation.shop
    if !@order_confirmation.blank?
      NetworkServices::WhatsappService.call(@shop,@order_confirmation)
      render json: @order_confirmation
    else
      render json: @order_confirmation.errors, status: :unprocessable_entity
    end
  end

  def prepaid2(params)
    puts params
    order_confirmation = OrderConfirmation.find_by(digest: params[:digest])

    if !order_confirmation.blank?   
      if !order_confirmation.draft_order_id.blank? #Already converted...
        return OrderConfirmation.find_by(order_id: order_confirmation.draft_order_id).order_status_url
        
      else
        if order_confirmation.shop.setting.payment_provider=='PHONEPE' #If Phonepe then double check the payment Status
          if NetworkServices::PhonepeStatusService.call(order_confirmation.shop,order_confirmation)==true
            return ShopifyServices::PrepaidOrderService.call(order_confirmation.shop, order_confirmation.id)
          else
            return NetworkServices::PhonepeLinkService.call(order_confirmation.shop, order_confirmation,false)
          end
        elsif order_confirmation.shop.setting.payment_provider=='PAYMOB' #If Paymob then double check the payment Status
          if NetworkServices::PaymobStatusService.call(order_confirmation.shop,order_confirmation)==true
            return ShopifyServices::PrepaidOrderService.call(order_confirmation.shop, order_confirmation.id)
          else
            return NetworkServices::PaymobLinkService.call(order_confirmation.shop, order_confirmation)
          end
        elsif order_confirmation.shop.setting.payment_provider=='GE_IDEA' #If Geidea then double check the payment Status
          if NetworkServices::GeideaStatusService.call(order_confirmation.shop,order_confirmation)==true
            return ShopifyServices::PrepaidOrderService.call(order_confirmation.shop, order_confirmation.id)
          else
            return NetworkServices::GeideaLinkService.call(order_confirmation.shop, order_confirmation)
          end
        elsif order_confirmation.shop.setting.payment_provider=='PAYU'
          if NetworkServices::PayuStatusService.call(order_confirmation.shop, order_confirmation)
            return ShopifyServices::PrepaidOrderService.call(order_confirmation.shop, order_confirmation.id)
          else
            return NetworkServices::PayuLinkService.call(order_confirmation.shop, order_confirmation)
          end
        elsif order_confirmation.shop.setting.payment_provider=='CASHFREE'
          if NetworkServices::CashfreeStatusService.call(order_confirmation.shop, order_confirmation)
            return ShopifyServices::PrepaidOrderService.call(order_confirmation.shop, order_confirmation.id)
          else
            return NetworkServices::CashfreeLinkService.call(order_confirmation.shop, order_confirmation)
          end
        else
          return ShopifyServices::PrepaidOrderService.call(order_confirmation.shop, order_confirmation.id)
        end
      end
    end
  end

  def prepaid
    puts params
    order_confirmation = OrderConfirmation.find_by(digest: params[:digest])

    if !order_confirmation.blank?   
      if !order_confirmation.draft_order_id.blank? #Already converted...
        redirect_to OrderConfirmation.find_by(order_id: order_confirmation.draft_order_id).order_status_url
        return   
      else
        if order_confirmation.shop.setting.payment_provider=='PHONEPE' #If Phonepe then double check the payment Status
          if NetworkServices::PhonepeStatusService.call(order_confirmation.shop,order_confirmation)
            redirect_to ShopifyServices::PrepaidOrderService.call(order_confirmation.shop, order_confirmation.id)
            return
          else
            redirect_to order_confirmation.order_status_url
            return
          end
        elsif order_confirmation.shop.setting.payment_provider=='PAYMOB' #If Paymob then double check the payment Status
          if NetworkServices::PaymobStatusService.call(order_confirmation.shop,order_confirmation)
            redirect_to ShopifyServices::PrepaidOrderService.call(order_confirmation.shop, order_confirmation.id)
            return
          else
            redirect_to order_confirmation.order_status_url
            return
          end
        elsif order_confirmation.shop.setting.payment_provider=='GE_IDEA' #If Geidea then double check the payment Status
          if NetworkServices::GeideaStatusService.call(order_confirmation.shop,order_confirmation)
            redirect_to ShopifyServices::PrepaidOrderService.call(order_confirmation.shop, order_confirmation.id)
            return
          else
            redirect_to order_confirmation.order_status_url
            return
          end
        elsif order_confirmation.shop.setting.payment_provider=='PAYU'
          if NetworkServices::PayuStatusService.call(order_confirmation.shop, order_confirmation)
            redirect_to ShopifyServices::PrepaidOrderService.call(order_confirmation.shop, order_confirmation.id)
            return
          else
            redirect_to order_confirmation.order_status_url
            return
          end
        elsif order_confirmation.shop.setting.payment_provider=='CASHFREE'
          if NetworkServices::CashfreeStatusService.call(order_confirmation.shop, order_confirmation)
            redirect_to ShopifyServices::PrepaidOrderService.call(order_confirmation.shop, order_confirmation.id)
            return
          else
            redirect_to order_confirmation.order_status_url
            return
          end
        else
          redirect_to ShopifyServices::PrepaidOrderService.call(order_confirmation.shop, order_confirmation.id)
          return
        end
      end
    end
  end

  def post_shipping_address
    if params['phone'].blank?
      render json: {response: 'Required params missing - Customer ID'}
    end
    phone = params['phone'].to_s.gsub(' ', '')
    phone = "+#{phone}" unless phone.strip.start_with?('+')
    customer = Customer.find_or_create_by(phone: phone)

    incoming_email = Customer.real_email(params['email'])
    customer.update(email: incoming_email) if incoming_email.present?

    if customer.blank?
      render json: { response: 'Invalid Phone Number' }
      return
    end

    shipping_address = params['shippingAdrress']
    if shipping_address.blank?
      render json: { response: 'Required params missing - Shipping Address' }
      return
    end

    # Add or update only; never delete existing addresses not in the payload.
    Array(shipping_address).each do |address|
      attrs = (address.respond_to?(:permit!) ? address.permit!.to_h : address.to_h)
                .slice(*CustomerAddress.column_names)
      id = attrs['id'].presence || attrs[:id].presence
      numeric_id = id.to_s.match?(/\A\d+\z/) ? id : nil
      if numeric_id.blank?
        customer.customer_addresses.create(attrs.except('id', :id))
      else
        addr_record = customer.customer_addresses.find_by(id: numeric_id)
        if addr_record.present?
          addr_record.update(attrs.except('id', :id))
        else
          customer.customer_addresses.create(attrs.except('id', :id))
        end
      end
    end

    Customer.invalidate_shipping_address_cache_by_phone(phone)
    render json: { response: 'Shipping Address updated successfully' }
  end

  def create_customer_login
    if ! (params['email'] && params['phone'] && params['shopifyCustomerId'] && params['password'] && params['shopifyDomain'])
      render json: {response: 'Required params missing - customer login create'}
      return
    end
    
    shop = Shop.find_by(shopify_domain:params['shopifyDomain'])
    if shop.blank?
      render json: {response: 'Invalid shop passed'}
      return
    end

    customer_login = CustomerLogin.where(phone:params['phone'], shopify_domain:params['shopifyDomain'])

    if !customer_login.blank?
      customer_login.first.update(email:params['email'], password: params['password'], phone: params['phone'], shopify_customer_id:params['shopifyCustomerId'], shopify_domain: params['shopifyDomain'])
      render json: {response: customer_login.first}
      return
    end

    customer_login = CustomerLogin.new(email:params['email'], password: params['password'], phone: params['phone'], shopify_customer_id:params['shopifyCustomerId'], shopify_domain: params['shopifyDomain'])
    if customer_login.save
      render json: {response: customer_login}
    else
      render json: {response: 'Error in creating customer please try again'}
    end
  rescue StandardError => e
    render json: {response: e}
  end

  def get_published_checkout_profile
    shop = Shop.find_by(shopify_domain:params['shopifyDomain'])
    if shop.blank?
      render json: {response: 'Invalid shop passed'}
      return
    end
    published_profile = ShopifyServices::CheckoutProfileGetService.call(shop)
    if published_profile==false
      render json: {error: true}
    else
      render json: {is_new_thankyou_page: JSON.parse(published_profile.to_json).to_h['typOspPagesActive']}
    end
  end

  def post_error_payload
    NetworkJobs::SlackNotificationJob.perform_async(params[:payload], 'global')
    render json: {success: true}
  end

  private

  # Skip Rails' session middleware on stateless public endpoints.
  def skip_rails_session
    request.session_options[:skip] = true
  end

  def normalize_public_shipping_phone_param
    raw = params[:phone].presence || params["phone"]
    return nil if raw.blank?

    p = raw.to_s.gsub(" ", "")
    p = "+#{p}" unless p.strip.start_with?("+")
    p
  end

  def india_v3_pricing?(record, shop)
    record.country_code.to_s.upcase == PricingV3India::COUNTRY_CODE &&
      PricingV3India.applies_to_shop_id?(shop&.id)
  end

  def partial_payment_rates_percent(shop)
    plan = ->(name) { Struct.new(:name).new(name) }
    to_percent = ->(rate) { (rate.to_f * 100).round(2) }
    {
      free: to_percent.call(PartialTransactionFee.free_rate(shop)),
      pro: to_percent.call(PartialTransactionFee.default_rate(nil, plan: plan.call("Pro"))),
      enterprise: to_percent.call(PartialTransactionFee.default_rate(nil, plan: plan.call("Enterprise"))),
      enterprise_plus: to_percent.call(PartialTransactionFee.default_rate(nil, plan: plan.call("Enterprise Plus")))
    }
  end

  def pricing_shop_for_sms_rate
    domain = params[:shop].presence || params[:shopify_domain].presence
    Shop.find_by(shopify_domain: domain) if domain.present?
  end
  
  # ✅ Handle cart with only BOGO items - return as-is
  def handle_pure_bogo_cart(input_cart)
    Rails.logger.info "Processing pure BOGO cart with #{input_cart.length} items"
    
    input_cart.map do |cart_item|
      # Add original variant ID for tracking
      cart_item['originalVariantId'] = cart_item['variantId']
      cart_item['originalCost'] = cart_item['cost'] || 0
      
      # Log BOGO item processing
      Rails.logger.info "BOGO Item: #{cart_item['title']} (#{cart_item['variantId']}) - Cost: #{cart_item['cost']}"
      
      cart_item
    end
  end

  # ✅ Handle mixed cart (BOGO + regular items)
# ✅ Handle mixed cart (BOGO + regular items) with proper mapping lookup
def handle_mixed_bogo_cart(shop, input_cart, session_id, cart_rule_id, cart_rule_set)
  Rails.logger.info "Processing mixed cart with BOGO and regular items"
  
  response_cart = []
  
  # Separate BOGO and regular items
  bogo_items = input_cart.select { |item| item['isBOGODiscount'] == true }
  regular_items = input_cart.reject { |item| item['isBOGODiscount'] == true }
  
  # Handle BOGO items - return as-is
  bogo_items.each do |bogo_item|
    bogo_item['originalVariantId'] = bogo_item['variantId']
    bogo_item['originalCost'] = bogo_item['cost'] || 0
    response_cart << bogo_item
    Rails.logger.info "BOGO Item processed: #{bogo_item['title']}"
  end
  
  # Handle regular items - try cached first, then fallback
  if regular_items.any?
    # ✅ FIXED: Calculate cart_hash ONCE for regular items and propagate
    regular_items_cart_hash = PartialCartService.generate_cart_hash(regular_items)
    Rails.logger.info "📦 Generated cart_hash for regular items: #{regular_items_cart_hash&.first(16)}... (calculated once)"
    
    if shop.setting&.partial_payment_enabled?
      cached_response = try_cached_partial_cart(shop, regular_items, session_id, cart_rule_id, regular_items_cart_hash)
      if cached_response
        Rails.logger.info "Using cached response for #{regular_items.length} regular items in mixed cart"
        response_cart.concat(cached_response)
        return response_cart
      end
    end
    
    # ✅ FIXED: Use the same fallback logic with proper mapping lookup (pass cart_hash)
    Rails.logger.info "Using fallback creation for #{regular_items.length} regular items in mixed cart"
    processed_regular_items = fallback_partial_cart_creation_for_mixed_cart(
      shop, regular_items, cart_rule_set, cart_rule_id, session_id, regular_items_cart_hash
    )
    response_cart.concat(processed_regular_items)
  end
  
  response_cart
end

# ✅ NEW METHOD: Fallback creation for mixed cart with mapping lookup
# ✅ FIXED: Accept cart_hash as parameter instead of recalculating
def fallback_partial_cart_creation_for_mixed_cart(shop, regular_items, cart_rule_set, cart_rule_id, session_id, cart_hash = nil)
  Rails.logger.info "Fallback creation for mixed cart regular items - session: #{session_id}"
  
  response_cart = []
  threads = []

  # ✅ FIXED: Use provided cart_hash, only calculate if not provided (backward compatibility)
  cart_hash ||= PartialCartService.generate_cart_hash(regular_items)
  Rails.logger.info "🔍 Using cart_hash: #{cart_hash&.first(16)}... (provided: #{cart_hash.present?})"
  
  # ✅ FIXED: Calculate overall_cart_value ONCE before the loop to ensure consistency
  overall_cart_value = PartialCartService.calculate_cart_value(regular_items)
  Rails.logger.info "💰 Overall cart value calculated: #{overall_cart_value} (calculated once for all products)"
  
  regular_items.each do |cart_item|
    quantity = cart_item['totalQuantity'].to_i
    cost = parse_cost(cart_item['cost']) || 0.0
    variant_with_quantity = "#{cart_item['variantId']}:#{quantity}"

    # ✅ FIXED: Look for existing mapping first using the correct logic
    existing_mapping = PartialProductMapping.where(
      shopify_domain: shop.shopify_domain,
      session_id: session_id,
      cart_hash: cart_hash,  # Use regular items cart hash
      is_deleted: false
    ).where("original_variant_ids::text LIKE ?", "%#{variant_with_quantity}%")
     .where(cart_rule_id: cart_rule_id)
     .first

    if existing_mapping
      # ✅ SAFEGUARD: Verify cart_hash matches to prevent using wrong mapping
      if existing_mapping.cart_hash != cart_hash
        Rails.logger.error "❌ CRITICAL: Found mapping with mismatched cart_hash in mixed cart! Expected: #{cart_hash&.first(8)}, Found: #{existing_mapping.cart_hash&.first(8)}"
        Rails.logger.error "   Mapping ID: #{existing_mapping.id}, Variant: #{variant_with_quantity}, Session: #{session_id}"
        existing_mapping = nil # Force creation of new mapping
      else
        Rails.logger.info "✅ Found existing mapping for #{variant_with_quantity} in mixed cart - using cached partial variant: #{existing_mapping.partial_variant_id}"
      end
    end
    
    if existing_mapping
      
      # Use existing mapping
      rule_set = PartialRuleSet.find_by(id: existing_mapping.cart_rule_id)
      partial_title = cart_item['title'].start_with?("Partial Payment for") ?
                        cart_item['title'] :
                        "Partial Payment for #{cart_item['title']}"
      partial_title = "#{partial_title} (#{rule_set.rule_name})" if rule_set

      # Calculate cost using existing mapping
      multiplier = 1.0
      if cart_rule_set.present?
        multiplier = cart_rule_set.amount_type == 'fixed' ? 
                      (cart_rule_set.amount.to_f / overall_cart_value) : 
                      (cart_rule_set.amount.to_f * 0.01)
      elsif rule_set
        multiplier = rule_set.amount_type == 'fixed' ? 1.0 : rule_set.amount.to_f * 0.01
      end

      partial_total = (multiplier * cost).round(2)
      partial_total = rule_set.amount.to_f if cart_rule_set.blank? && rule_set&.amount_type == 'fixed'

      # Update the mapping with the current partial price
      existing_mapping.update(partial_price: partial_total) if existing_mapping.partial_price != partial_total

      response_cart << {
        "originalVariantId" => cart_item['variantId'],
        "cost" => partial_total,
        "title" => partial_title,
        "variantId" => existing_mapping.partial_variant_id,
        "totalQuantity" => quantity,
        "originalCost" => cost,
        "ruleId" => rule_set&.id
      }
      
      Rails.logger.info "✅ Using cached mapping in mixed cart - skipping product creation for #{cart_item['variantId']}"
      next # Skip to next item since we found cached mapping
    end

    # Only create new product if no existing mapping found
    threads << Thread.new do
      rule_set = cart_rule_set || PartialRuleSet.find_by(id: cart_item['ruleId'])

      # Skip items without rules and without cost
      if rule_set.nil? && cart_item['cost'].blank?
        Rails.logger.info "Skipping regular item #{cart_item['variantId']} in mixed cart - no rule and no cost"
        next nil
      end

      # Skip items that don't have rules but were validated above
      next nil if rule_set.nil? && cart_item['ruleId'].present?

      multiplier = 1.0
      if cart_rule_set.present?
        multiplier = cart_rule_set.amount_type == 'fixed' ? 
                      (cart_rule_set.amount.to_f / overall_cart_value) : 
                      (cart_rule_set.amount.to_f * 0.01)
      elsif rule_set
        multiplier = rule_set.amount_type == 'fixed' ? 1.0 : rule_set.amount.to_f * 0.01
      end

      partial_total = (multiplier * cost).round(2)
      partial_total = rule_set.amount.to_f if cart_rule_set.blank? && rule_set&.amount_type == 'fixed'

      partial_title = cart_item['title'].start_with?("Partial Payment for") ?
                        cart_item['title'] :
                        "Partial Payment for #{cart_item['title']}"

      # Add unique identifier to prevent handle conflicts
      timestamp = Time.current.to_i
      random_id = rand(1000)
      partial_title = "#{partial_title} #{timestamp}-#{random_id}"

      Rails.logger.info "🔄 Creating NEW partial product for #{cart_item['variantId']} in mixed cart - no existing mapping found"

      begin
        generated_variant_id = ShopifyServices::PartialProductCreateService.call(
          shop,
          partial_title,
          partial_total,
          ["#{cart_item['variantId']}:#{quantity}"],
          cart_item['imageUrl'],
          cost,
          session_id: session_id,
          cart_hash: cart_hash,  # Use regular items cart hash
          cart_rule_id: cart_rule_id || cart_item['ruleId']
        )

        {
          "originalVariantId" => cart_item['variantId'],
          "cost" => partial_total,
          "title" => partial_title,
          "variantId" => generated_variant_id,
          "totalQuantity" => quantity,
          "originalCost" => cost,
          "ruleId" => rule_set&.id
        }
      rescue => e
        Rails.logger.error "Failed to create partial product for regular item #{cart_item['variantId']} in mixed cart: #{e.message}"
        
        SlackNotifyJob.perform_async(
          ":boom: Mixed Cart Partial Product Creation Failed (#{Rails.env})\n" \
          "🛍️ Shop: #{shop.shopify_domain}\n" \
          "📦 Item: #{cart_item['title']} (#{cart_item['variantId']})\n" \
          "💰 Cost: #{cost}, Partial: #{partial_total}\n" \
          "📋 Rule: #{rule_set&.rule_name || 'None'}\n" \
          "🧾 Session: #{session_id}\n" \
          "💥 Error: #{e.message}"
        )
        
        nil # Return nil for failed items
      end
    end
  end

  threads.each(&:join)

  # Collect successful results from threads
  threads.each do |thread|
    result = thread.value
    response_cart << result if result.present?
  end

  # Handle unmapped regular items with no rule but with cost
  regular_items.each do |cart_item|
    # Check if this item was already processed above
    already_processed = response_cart.any? { |item| item["originalVariantId"] == cart_item['variantId'] }
    
    if !already_processed && cart_item['ruleId'].blank? && cart_rule_id.blank?
      cart_item['originalVariantId'] = cart_item['variantId']
      cart_item['originalCost'] = cart_item['cost'] || 0
      response_cart << cart_item
    end
  end

  response_cart
end

  # ✅ Process regular items in mixed cart
  def process_regular_items_for_mixed_cart(shop, regular_items, cart_rule_set, cart_rule_id, session_id)
    overall_cart_value = 0.0
    regular_response = []
    threads = []

    # Calculate overall cart value for regular items
    regular_items.each do |cart_item|
      quantity = cart_item['totalQuantity'].to_i
      cost = parse_cost(cart_item['cost']) || 0.0
      overall_cart_value += cost * quantity
    end

    # Process each regular item
    regular_items.each do |cart_item|
      threads << Thread.new do
        rule_set = cart_rule_set || PartialRuleSet.find_by(id: cart_item['ruleId'])

        # Skip items without rules and without cost
        if rule_set.nil? && cart_item['cost'].blank?
          Rails.logger.info "Skipping regular item #{cart_item['variantId']} - no rule and no cost"
          next nil
        end

        quantity = cart_item['totalQuantity'].to_i
        cost = parse_cost(cart_item['cost']) || 0.0

        multiplier = 1.0
        if cart_rule_set.present?
          multiplier = cart_rule_set.amount_type == 'fixed' ? 
                        (cart_rule_set.amount.to_f / overall_cart_value) : 
                        (cart_rule_set.amount.to_f * 0.01)
        elsif rule_set
          multiplier = rule_set.amount_type == 'fixed' ? 1.0 : rule_set.amount.to_f * 0.01
        end

        partial_total = (multiplier * cost).round(2)
        partial_total = rule_set.amount.to_f if cart_rule_set.blank? && rule_set&.amount_type == 'fixed'

        partial_title = cart_item['title'].start_with?("Partial Payment for") ?
                          cart_item['title'] :
                          "Partial Payment for #{cart_item['title']}"

        # Add unique identifier to prevent handle conflicts
        timestamp = Time.current.to_i
        random_id = rand(1000)
        partial_title = "#{partial_title} #{timestamp}-#{random_id}"

        # ✅ FIXED: Use the same cart_hash passed to this method, don't recalculate
        # mixed_cart_hash = PartialCartService.generate_cart_hash(regular_items) # REMOVED - use cart_hash parameter

        begin
          generated_variant_id = ShopifyServices::PartialProductCreateService.call(
            shop,
            partial_title,
            partial_total,
            ["#{cart_item['variantId']}:#{quantity}"],
            cart_item['imageUrl'],
            cost,
            session_id: session_id,
            cart_hash: cart_hash, # ✅ FIXED: Use the same cart_hash passed to this method
            cart_rule_id: cart_rule_id || cart_item['ruleId']
          )

          {
            "originalVariantId" => cart_item['variantId'],
            "cost" => partial_total,
            "title" => partial_title,
            "variantId" => generated_variant_id,
            "totalQuantity" => quantity,
            "originalCost" => cost,
            "ruleId" => rule_set&.id
          }
        rescue => e
          Rails.logger.error "Failed to create partial product for regular item #{cart_item['variantId']} in mixed cart: #{e.message}"
          
          SlackNotifyJob.perform_async(
            ":boom: Mixed Cart Partial Product Creation Failed (#{Rails.env})\n" \
            "🛍️ Shop: #{shop.shopify_domain}\n" \
            "📦 Item: #{cart_item['title']} (#{cart_item['variantId']})\n" \
            "💰 Cost: #{cost}, Partial: #{partial_total}\n" \
            "📋 Rule: #{rule_set&.rule_name || 'None'}\n" \
            "🧾 Session: #{session_id}\n" \
            "💥 Error: #{e.message}"
          )
          
          nil # Return nil for failed items
        end
      end
    end

    threads.each(&:join)

    # Collect successful results
    threads.each do |thread|
      result = thread.value
      regular_response << result if result.present?
    end

    # Handle unmapped regular items with no rule but with cost
    regular_items.each do |cart_item|
      if cart_item['ruleId'].blank? && cart_rule_id.blank?
        cart_item['originalVariantId'] = cart_item['variantId']
        cart_item['originalCost'] = cart_item['cost'] || 0
        regular_response << cart_item
      end
    end

    regular_response
  end
  
  # ✅ Comprehensive cart item validation
  def validate_cart_items(input_cart, cart_rule_id, shop)
    validation_errors = []
    
    # Validate cart structure
    unless input_cart.is_a?(Array)
      validation_errors << {
        global: true,
        errors: ["inputCart must be an array"]
      }
      return {
        valid: false,
        error: "Cart validation failed - invalid structure",
        details: validation_errors
      }
    end
    
    if input_cart.empty?
      validation_errors << {
        global: true,
        errors: ["inputCart cannot be empty"]
      }
      return {
        valid: false,
        error: "Cart validation failed - empty cart",
        details: validation_errors
      }
    end
    
    if input_cart.length > 50 # Reasonable limit
      validation_errors << {
        global: true,
        errors: ["inputCart cannot contain more than 50 items"]
      }
    end
    
    input_cart.each_with_index do |cart_item, index|
      item_errors = []
      
      # Required fields for all items
      if cart_item['variantId'].blank?
        item_errors << "variantId is required"
      end
      
      if cart_item['title'].blank?
        item_errors << "title is required"
      end
      
      if cart_item['totalQuantity'].blank? || cart_item['totalQuantity'].to_i <= 0
        item_errors << "totalQuantity must be a positive number"
      elsif cart_item['totalQuantity'].to_i > 999
        item_errors << "totalQuantity cannot exceed 999"
      end
      
      # ✅ Enhanced validation for items with rules
      has_rule = cart_item['ruleId'].present? || cart_rule_id.present?
      
      if has_rule
        # Cost is REQUIRED for items with rules
        if cart_item['cost'].blank?
          item_errors << "cost is required for items with ruleId or when cartRuleId is provided"
        else
          # Validate cost format and value
          cost = parse_cost(cart_item['cost'])
          if cost.nil?
            item_errors << "cost must be a valid number"
          elsif cost < 0
            item_errors << "cost cannot be negative"
          else
            # ✅ Special validation for $0 costs
            if cost == 0
              rule_validation = validate_zero_cost_rule(cart_item, cart_rule_id, shop)
              unless rule_validation[:valid]
                item_errors << rule_validation[:error]
              end
            end
          end
        end
        
        # Validate rule exists and is applicable
        if cart_item['ruleId'].present?
          individual_rule = PartialRuleSet.find_by(id: cart_item['ruleId'], shop_id: shop.id)
          if individual_rule.blank?
            item_errors << "ruleId #{cart_item['ruleId']} not found for this shop"
          elsif individual_rule.is_cart_rule?
            item_errors << "ruleId #{cart_item['ruleId']} is a cart rule, not an individual rule"
          elsif !individual_rule.is_enabled?
            item_errors << "ruleId #{cart_item['ruleId']} is disabled"
          end
        end
      else
        # Items without rules don't need cost validation but can have cost
        if cart_item['cost'].present?
          cost = parse_cost(cart_item['cost'])
          if cost.nil?
            item_errors << "cost must be a valid number when provided"
          elsif cost < 0
            item_errors << "cost cannot be negative"
          end
        end
      end
      
      # Add item-specific errors to validation
      if item_errors.any?
        validation_errors << {
          item_index: index,
          variant_id: cart_item['variantId'],
          title: cart_item['title'],
          errors: item_errors
        }
      end
    end
    
    # Global validation
    if cart_rule_id.present? && input_cart.any? { |item| item['ruleId'].present? }
      validation_errors << {
        global: true,
        errors: ["Cannot mix cartRuleId with individual item ruleIds"]
      }
    end
    
    # Validate cart rule exists if provided
    if cart_rule_id.present?
      cart_rule = PartialRuleSet.find_by(id: cart_rule_id, is_cart_rule: true, shop_id: shop.id)
      if cart_rule.blank?
        validation_errors << {
          global: true,
          errors: ["cartRuleId #{cart_rule_id} not found or is not a cart rule for this shop"]
        }
      elsif !cart_rule.is_enabled?
        validation_errors << {
          global: true,
          errors: ["cartRuleId #{cart_rule_id} is disabled"]
        }
      end
    end
    
    if validation_errors.any?
      {
        valid: false,
        error: "Cart validation failed - #{validation_errors.count} error(s) found",
        details: validation_errors
      }
    else
      { valid: true }
    end
  end

  # ✅ Validate $0 costs against rule configuration
  def validate_zero_cost_rule(cart_item, cart_rule_id, shop)
    if cart_item['isBOGODiscount'] == true
      return { valid: true }
    end
    rule_id = cart_item['ruleId'] || cart_rule_id
    
    unless rule_id.present?
      return {
        valid: false,
        error: "cost cannot be $0 without a valid rule"
      }
    end
    
    rule_set = PartialRuleSet.find_by(id: rule_id, shop_id: shop.id)
    unless rule_set
      return {
        valid: false,
        error: "rule not found for $0 cost validation"
      }
    end
    
    # Check if rule allows $0 cost
    allows_zero = (
      rule_set.amount.to_f == 0 ||
      (rule_set.amount_type == 'percentage' && rule_set.amount.to_f == 0) ||
      (rule_set.amount_type == 'fixed' && rule_set.amount.to_f == 0) 

    )
    
    unless allows_zero
      return {
        valid: false,
        error: "cost cannot be $0 for rule '#{rule_set.rule_name}' (#{rule_set.amount_type}: #{rule_set.amount})"
      }
    end
    
    { valid: true }
  end

  # ✅ Safe cost parsing
  def parse_cost(cost_value)
    return nil if cost_value.blank?
    
    if cost_value.is_a?(String)
      # Remove currency symbols and clean
      cleaned_cost = cost_value.gsub(/[^\d.]/, '')
      return nil if cleaned_cost.blank?
      cleaned_cost.to_f
    elsif cost_value.is_a?(Numeric)
      cost_value.to_f
    else
      nil
    end
  rescue
    nil
  end

  # ENHANCED: Complete set validation for cached partial cart
  # ✅ FIXED: Accept cart_hash as parameter instead of recalculating
  def try_cached_partial_cart(shop, input_cart, session_id, cart_rule_id, cart_hash = nil)
    return nil unless shop.setting&.partial_payment_enabled?
    return nil if session_id.blank?

    # ✅ FIXED: Use provided cart_hash, only calculate if not provided (backward compatibility)
    cart_hash ||= PartialCartService.generate_cart_hash(input_cart)
    Rails.logger.info "🔍 Using cart_hash: #{cart_hash&.first(16)}... (provided: #{cart_hash.present?})"
    
    # If specific cart rule requested, validate that rule exists and is applicable
    if cart_rule_id.present?
      cart_rule_set = PartialRuleSet.find_by(id: cart_rule_id, is_cart_rule: true, shop_id: shop.id)
      return nil if cart_rule_set.blank?
      
      overall_cart_value = PartialCartService.calculate_cart_value(input_cart)
      return nil unless PartialCartService.cart_rule_applies?(cart_rule_set, overall_cart_value)
    end

    Rails.logger.info "Checking cached mappings for cart_hash: #{cart_hash}, session: #{session_id}, rule: #{cart_rule_id}"

    # CRITICAL: Validate that ALL products have mappings before using cached results
    missing_products = []
    
    input_cart.each do |cart_item|
      variant_id = cart_item['variantId']
      quantity = cart_item['totalQuantity'] || cart_item['quantity'] || 1
      
      # Determine which rule to look for
      if cart_rule_id.present?
        target_rule_id = cart_rule_id
        is_cart_rule = true
      elsif cart_item['ruleId'].present?
        target_rule_id = cart_item['ruleId']
        is_cart_rule = false
      else
        # Skip validation for items without rules
        next
      end
      
      # Find mapping for this specific item
      mapping = PartialCartService.find_appropriate_mapping(
        shop, 
        cart_item, 
        cart_hash, 
        session_id, 
        target_rule_id, 
        is_cart_rule
      )
      
      if mapping.nil?
        missing_products << {
          variant_id: variant_id,
          title: cart_item['title'],
          quantity: quantity,
          rule_id: target_rule_id
        }
      end
    end
    
    # If ANY products with rules are missing mappings, don't use cached results
    if missing_products.any?
      Rails.logger.warn "Incomplete mappings found - missing #{missing_products.count} products with rules:"
      missing_products.each do |product|
        Rails.logger.warn "  Missing: #{product[:variant_id]} (#{product[:title]}) with rule #{product[:rule_id]}"
      end
      
      # Check if pre-creation is still in progress
      cache_key = "pre_create_lock_#{shop.id}_#{cart_hash}_#{session_id}"
      if Rails.cache.exist?(cache_key)
        Rails.logger.info "Pre-creation still in progress, will retry cached lookup"
      else
        Rails.logger.warn "Pre-creation completed but mappings incomplete - forcing fallback"
      end
      
      return nil # Force fallback to ensure all products are created
    end

    Rails.logger.info "✅ All products with rules have cached mappings - using pre-created products"

    # All products have mappings - proceed with cached logic
    response_cart = []
    
    input_cart.each do |cart_item|
      if cart_item['ruleId'].blank? && cart_rule_id.blank?
        # Handle unmapped items with no rule
        cart_item['originalVariantId'] = cart_item['variantId']
        cart_item['originalCost'] = cart_item['cost']
        response_cart << cart_item
      else
        # Find the appropriate pre-created mapping
        mapping = find_cached_mapping(shop, cart_item, cart_hash, session_id, cart_rule_id)
        
        if mapping
          response_cart << build_response_from_mapping(cart_item, mapping, input_cart)
        else
          # This shouldn't happen after validation, but safety check
          Rails.logger.error "Mapping disappeared after validation for variant #{cart_item['variantId']}"
          return nil
        end
      end
    end
    
    response_cart.any? ? response_cart : nil
  end
  
  def find_cached_mapping(shop, cart_item, cart_hash, session_id, cart_rule_id)
    # Determine which rule to look for
    if cart_rule_id.present?
      # Cart rule takes precedence
      target_rule_id = cart_rule_id
      is_cart_rule = true
    elsif cart_item['ruleId'].present?
      # Individual item rule
      target_rule_id = cart_item['ruleId']
      is_cart_rule = false
    else
      return nil
    end
  
    # Find the specific mapping for this rule and session
    PartialCartService.find_appropriate_mapping(
      shop, 
      cart_item, 
      cart_hash, 
      session_id,
      target_rule_id, 
      is_cart_rule
    )
  end
  
  def build_response_from_mapping(cart_item, mapping, input_cart)
    # Get the rule set from cart_rule_id
    rule_set = PartialRuleSet.find_by(id: mapping.cart_rule_id)
    
    partial_title = cart_item['title'].start_with?("Partial Payment for") ?
                      cart_item['title'] :
                      "Partial Payment for #{cart_item['title']}"
    
    # Add rule name if available
    partial_title = "#{partial_title} (#{rule_set.rule_name})" if rule_set
  
    {
      "originalVariantId" => cart_item['variantId'],
      "cost" => calculate_cost_from_cached_mapping(cart_item, mapping, rule_set, input_cart),
      "title" => partial_title,
      "variantId" => mapping.partial_variant_id,
      "totalQuantity" => cart_item['totalQuantity'],
      "originalCost" => cart_item['cost'],
      "ruleId" => rule_set&.id
    }
  end
  
  def calculate_cost_from_cached_mapping(cart_item, mapping, rule_set, input_cart)
    # Get the rule set if not provided
    rule_set ||= PartialRuleSet.find_by(id: mapping.cart_rule_id)
    
    return cart_item['cost'].to_f unless rule_set
  
    quantity = cart_item['totalQuantity'].to_i
    cost = cart_item['cost'].to_f
  
    if rule_set.is_cart_rule?
      # For cart rules, we need to recalculate based on current cart value
      overall_cart_value = calculate_overall_cart_value_from_input(input_cart)
      multiplier = rule_set.amount_type == 'fixed' ? 
                    (rule_set.amount.to_f / overall_cart_value) : 
                    (rule_set.amount.to_f * 0.01)
      (multiplier * cost).round(2)
    else
      # For individual rules, calculation is simpler
      multiplier = rule_set.amount_type == 'fixed' ? 1.0 : rule_set.amount.to_f * 0.01
      partial_total = (multiplier * cost).round(2)
      rule_set.amount_type == 'fixed' ? rule_set.amount.to_f : partial_total
    end
  end
  
  def calculate_overall_cart_value_from_input(input_cart)
    input_cart.sum do |item|
      quantity = item['totalQuantity'].to_i
      cost = item['cost'].to_f
      cost * quantity
    end
  end
  
  # ✅ Enhanced fallback creation with better validation and error handling
 # ✅ Enhanced fallback creation with FIXED mapping lookup
# ✅ FIXED: Accept cart_hash as parameter instead of recalculating
def fallback_partial_cart_creation(shop, input_cart, cart_rule_set, cart_rule_id, session_id, cart_hash = nil)
  Rails.logger.info "Falling back to original cart creation logic for session: #{session_id}"
  
  response_cart = []
  threads = []

  # ✅ FIXED: Use provided cart_hash, only calculate if not provided (backward compatibility)
  cart_hash ||= PartialCartService.generate_cart_hash(input_cart)
  Rails.logger.info "🔍 Using cart_hash: #{cart_hash&.first(16)}... (provided: #{cart_hash.present?})"
  
  # ✅ FIXED: Calculate overall_cart_value ONCE before the loop to ensure consistency
  overall_cart_value = PartialCartService.calculate_cart_value(input_cart)
  Rails.logger.info "💰 Overall cart value calculated: #{overall_cart_value} (calculated once for all products)"
  
  input_cart.each do |cart_item|
    quantity = cart_item['totalQuantity'].to_i
    cost = parse_cost(cart_item['cost']) || 0.0
    variant_with_quantity = "#{cart_item['variantId']}:#{quantity}"

    # ✅ FIXED: Look for existing mapping first using the correct logic
    existing_mapping = PartialProductMapping.where(
      shopify_domain: shop.shopify_domain,
      session_id: session_id,
      cart_hash: cart_hash,
      is_deleted: false
    ).where("original_variant_ids::text LIKE ?", "%#{variant_with_quantity}%")
     .where(cart_rule_id: cart_rule_id)
     .first

    if existing_mapping
      # ✅ SAFEGUARD: Verify cart_hash matches to prevent using wrong mapping
      if existing_mapping.cart_hash != cart_hash
        Rails.logger.error "❌ CRITICAL: Found mapping with mismatched cart_hash! Expected: #{cart_hash&.first(8)}, Found: #{existing_mapping.cart_hash&.first(8)}"
        Rails.logger.error "   Mapping ID: #{existing_mapping.id}, Variant: #{variant_with_quantity}, Session: #{session_id}"
        existing_mapping = nil # Force creation of new mapping
      else
        Rails.logger.info "✅ Found existing mapping for #{variant_with_quantity} - using cached partial variant: #{existing_mapping.partial_variant_id}"
      end
    end
    
    if existing_mapping
      # Use existing mapping
      rule_set = PartialRuleSet.find_by(id: existing_mapping.cart_rule_id)
      partial_title = cart_item['title'].start_with?("Partial Payment for") ?
                        cart_item['title'] :
                        "Partial Payment for #{cart_item['title']}"
      partial_title = "#{partial_title} (#{rule_set.rule_name})" if rule_set

      # Calculate cost using existing mapping
      multiplier = 1.0
      if cart_rule_set.present?
        multiplier = cart_rule_set.amount_type == 'fixed' ? 
                      (cart_rule_set.amount.to_f / overall_cart_value) : 
                      (cart_rule_set.amount.to_f * 0.01)
      elsif rule_set
        multiplier = rule_set.amount_type == 'fixed' ? 1.0 : rule_set.amount.to_f * 0.01
      end

      partial_total = (multiplier * cost).round(2)
      partial_total = rule_set.amount.to_f if cart_rule_set.blank? && rule_set&.amount_type == 'fixed'

      # Update the mapping with the current partial price
      existing_mapping.update(partial_price: partial_total) if existing_mapping.partial_price != partial_total

      response_cart << {
        "originalVariantId" => cart_item['variantId'],
        "cost" => partial_total,
        "title" => partial_title,
        "variantId" => existing_mapping.partial_variant_id,
        "totalQuantity" => quantity,
        "originalCost" => cost,
        "ruleId" => rule_set&.id
      }
      
      Rails.logger.info "✅ Using cached mapping - skipping product creation for #{cart_item['variantId']}"
      next # Skip to next item since we found cached mapping
    end

    # Only create new product if no existing mapping found
    threads << Thread.new do
      rule_set = cart_rule_set || PartialRuleSet.find_by(id: cart_item['ruleId'])

      # ✅ Skip items without rules and without cost
      if rule_set.nil? && cart_item['cost'].blank?
        Rails.logger.info "Skipping item #{cart_item['variantId']} - no rule and no cost"
        next nil
      end

      # ✅ Skip items that don't have rules but were validated above
      next nil if rule_set.nil? && cart_item['ruleId'].present?

      multiplier = 1.0
      if cart_rule_set.present?
        multiplier = cart_rule_set.amount_type == 'fixed' ? 
                      (cart_rule_set.amount.to_f / overall_cart_value) : 
                      (cart_rule_set.amount.to_f * 0.01)
      elsif rule_set
        multiplier = rule_set.amount_type == 'fixed' ? 1.0 : rule_set.amount.to_f * 0.01
      end

      partial_total = (multiplier * cost).round(2)
      partial_total = rule_set.amount.to_f if cart_rule_set.blank? && rule_set&.amount_type == 'fixed'

      partial_title = cart_item['title'].start_with?("Partial Payment for") ?
                        cart_item['title'] :
                        "Partial Payment for #{cart_item['title']}"

      # Add unique identifier to prevent handle conflicts
      timestamp = Time.current.to_i
      random_id = rand(1000)
      partial_title = "#{partial_title} #{timestamp}-#{random_id}"

      Rails.logger.info "🔄 Creating NEW partial product for #{cart_item['variantId']} - no existing mapping found"

      begin
        # ✅ Use the enhanced service call with proper validation
        # ✅ FIXED: Pass the same cart_hash that was calculated at request start
        generated_variant_id = ShopifyServices::PartialProductCreateService.call(
          shop,
          partial_title,
          partial_total,
          ["#{cart_item['variantId']}:#{quantity}"],
          cart_item['imageUrl'],
          cost,
          session_id: session_id,
          cart_hash: cart_hash, # Use the same cart_hash from request start
          cart_rule_id: cart_rule_id || cart_item['ruleId']
        )

        {
          "originalVariantId" => cart_item['variantId'],
          "cost" => partial_total,
          "title" => partial_title,
          "variantId" => generated_variant_id,
          "totalQuantity" => quantity,
          "originalCost" => cost,
          "ruleId" => rule_set&.id
        }
      rescue => e
        Rails.logger.error "Failed to create partial product for item #{cart_item['variantId']}: #{e.message}"
        
        # Send Slack notification for creation failures
        SlackNotifyJob.perform_async(
          ":boom: Partial Product Creation Failed (#{Rails.env})\n" \
          "🛍️ Shop: #{shop.shopify_domain}\n" \
          "📦 Item: #{cart_item['title']} (#{cart_item['variantId']})\n" \
          "💰 Cost: #{cost}, Partial: #{partial_total}\n" \
          "📋 Rule: #{rule_set&.rule_name || 'None'}\n" \
          "🧾 Session: #{session_id}\n" \
          "💥 Error: #{e.message}"
        )
        
        nil # Return nil for failed items
      end
    end
  end

  threads.each(&:join)

  # Collect successful results from threads
  threads.each do |thread|
    result = thread.value
    response_cart << result if result.present?
  end

  # ✅ Handle unmapped items with no rule but with cost
  input_cart.each do |cart_item|
    # Check if this item was already processed above
    already_processed = response_cart.any? { |item| item["originalVariantId"] == cart_item['variantId'] }
    
    if !already_processed && cart_item['ruleId'].blank? && cart_rule_id.blank?
      cart_item['originalVariantId'] = cart_item['variantId']
      cart_item['originalCost'] = cart_item['cost'] || 0
      response_cart << cart_item
    end
  end

  render json: { response: response_cart }
end

  def call_sms_twillio(order_confirmation)
    NetworkJobs::SendSmsJob.perform_async(
      order_confirmation.shop.id,
      order_confirmation.id
    )
  end

  def call_ivr_twillio(order_confirmation, shop)
    if !order_confirmation.customer_number.blank? && order_confirmation.notif_count < MAX_TRIES
      request = build_twiml(
        shop.primary_locale&.to_sym,
        shop.setting.ivr_introduction,
        shop.setting.ivr_confirm_message,
        shop.setting.ivr_cancel_message,
        '/twillio/ivr_webhook'
      )
      resp = TwilioServices::IvrCallService.call({
                                                   from: ENV.fetch("TWILIO_PHONE_NUMBER", nil),
                                                   to: order_confirmation.customer_number,
                                                   twiml: request
                                                 })
      order_confirmation.update(ivr_sid: resp.sid)
      order_confirmation.increment!(:notif_count)
      TwilioLog.create(
        sid: resp.sid,
        ver_type: 'IVR',
        country_code: order_confirmation.country_code,
        customer_number: order_confirmation.customer_number,
        status: resp.sid ? 'SUCCESS' : resp.error,
        order_confirmation: order_confirmation,
        shop: shop
      )
    else
      SlackNotifyJob.perform_async(
        ":rage:  (#{Rails.env})\n  *Error* Order reached max tries order_id #{order_confirmation.order_id}"
      )
    end
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_order_confirmation
    @order_confirmation = OrderConfirmation.find_by(order_id: params[:id])
  end

  # Only allow a list of trusted parameters through.
  def order_confirmation_params
    params.require(:order_confirmation).permit(:order_id, :order_amount, :customer_name, :customer_number)
  end

  def get_phone_from_shipping
    phone_number = clean_phone_number(
      params['shipping_address']['phone'],
      params['shipping_address']['country_code'].downcase
    )
  rescue StandardError => e
    phone_number = ''
  end

  def set_shop
    @shop = Shop.find_by(
      shopify_domain: request.headers['X-Shopify-Shop-Domain']
    )
  end

  def set_shop_webhook
    @shop = Shop.find_by(
      shopify_domain: request.headers['X-Shopify-Shop-Domain']
    )
  end

  def verify_webhook
    calculated_hmac = Base64.strict_encode64(
      OpenSSL::HMAC.digest('sha256', ENV.fetch("SHOPIFY_API_SECRET", nil), request.raw_post)
    )
    verified = ActiveSupport::SecurityUtils.secure_compare(
      calculated_hmac, request.headers['HTTP_X_SHOPIFY_HMAC_SHA256']
    )
    raise 'Not Authorized to perform this action' unless verified
  end

  def clean_phone_number(phone, country_code)
    if !phone.blank?
      phone = phone.tr('^0-9', '').sub!(/^0*/, '')
    end
    Phonelib.parse(phone, country_code).to_s
  rescue Exception => e
    SlackNotifyJob.perform_async(
      ":rage:  (#{Rails.env})\n *Error* Phonelib parse \n Phone: #{phone}  \n country_code: #{country_code} \n error: #{e.message}"
    )
    phone
  end
end