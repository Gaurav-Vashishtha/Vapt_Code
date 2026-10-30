# app/services/partial_cart_service.rb

class PartialCartService
  def self.generate_cart_hash(cart_details)
    # Create hash based only on cart contents (not rules, since we create for all rules)
    cart_signature = cart_details.map do |item|
      {
        variant_id: item['variantId'] || item[:variantId],
        quantity: item['totalQuantity'] || item[:totalQuantity] || item['quantity'] || item[:quantity],
        cost: item['cost'] || item[:cost],
        title: item['title'] || item[:title],
        image_url: item['imageUrl'] || item[:imageUrl]
      }
    end.sort_by { |item| item[:variant_id] }
    
    Digest::SHA256.hexdigest(cart_signature.to_json)
  end

  def self.find_existing_mappings(shopify_domain, cart_hash, session_id, cart_rule_id = nil)
    query = PartialProductMapping.where(
      shopify_domain: shopify_domain,
      cart_hash: cart_hash,
      session_id: session_id,
      is_deleted: false
    )
    
    query = query.where(cart_rule_id: cart_rule_id) if cart_rule_id.present?
    query
  end

  def self.pre_create_partial_products(shop, cart_details, session_id)
    return unless shop.setting&.partial_payment_enabled?
    return if session_id.blank?

    cart_hash = generate_cart_hash(cart_details)
    
    # Check if any mappings already exist for this cart state and session
    existing_mappings = PartialProductMapping.where(
      shopify_domain: shop.shopify_domain,
      cart_hash: cart_hash,
      session_id: session_id,
      is_deleted: false
    )
    
    if existing_mappings.exists?
      Rails.logger.info "Mappings already exist for cart_hash: #{cart_hash}, session: #{session_id}"
      return
    end

    # Lock to prevent concurrent creation
    Rails.cache.fetch("pre_create_lock_#{shop.id}_#{cart_hash}_#{session_id}", expires_in: 30.minutes) do
      create_all_rule_combinations_async(shop, cart_details, cart_hash, session_id)
      true
    end
  end

  private

  def self.create_all_rule_combinations_async(shop, cart_details, cart_hash, session_id)
    # Create products in background to avoid blocking the response
    Thread.new do
      begin
        ActiveRecord::Base.connection_pool.with_connection do
          process_all_rule_combinations(shop, cart_details, cart_hash, session_id)
        end
      rescue => e
        Rails.logger.error "Pre-creation failed: #{e.message}"
        SlackNotifyJob.perform_async(
          ":warning: Pre-creation failed\n🛍️ Shop: #{shop.shopify_domain}\n🔖 Cart Hash: #{cart_hash}\n📱 Session: #{session_id}\n💥 Error: #{e.message}"
        )
      ensure
        ActiveRecord::Base.connection_pool.release_connection
      end
    end
  end

  def self.process_all_rule_combinations(shop, cart_details, cart_hash, session_id)
    overall_cart_value = calculate_cart_value(cart_details)
    
    # Get cart rules with exclusions
    cart_rules = PartialRuleSet.where(shop_id: shop.id, is_enabled: true, is_cart_rule: true)
                               .where.not(amount_type: 'cod') # Exclude COD rules
                               .where.not(amount_type: 'percentage', amount: 100) # Exclude 100% percentage rules
    
    # Filter out rules with cart range restrictions that don't match
    cart_rules = cart_rules.select do |rule|
      # Skip rules that have min/max cart range set (> 0) and overall_cart_value is outside the range
      if rule.min_cart_range.present? && rule.min_cart_range > 0 && overall_cart_value < rule.min_cart_range
        false
      elsif rule.max_cart_range.present? && rule.max_cart_range > 0 && overall_cart_value > rule.max_cart_range
        false
      else
        true
      end
    end
    
    total_products_created = 0
    
    # Create products for cart rules only
    total_products_created += create_cart_rule_products(shop, cart_details, cart_hash, session_id, cart_rules, overall_cart_value)
    
    Rails.logger.info "Pre-created #{total_products_created} partial products for #{cart_details.length} items with #{cart_rules.count} cart rules (session: #{session_id})"
  end

  def self.create_individual_rule_products(shop, cart_details, cart_hash, session_id, rules, overall_cart_value)
    products_created = 0
    
    Rails.logger.info "Processing #{rules.count} individual rules"
    
    cart_details.each do |cart_item|
      Rails.logger.info "Processing item: #{cart_item['variantId']} (#{cart_item['title']})"
      
      rules.each do |rule_set|
        Rails.logger.info "Checking individual rule #{rule_set.id} (#{rule_set.rule_name}) for item #{cart_item['variantId']}"
        
        unless rule_applies_to_product?(rule_set, cart_item)
          Rails.logger.info "Rule #{rule_set.id} does not apply to product #{cart_item['variantId']}"
          next
        end
        
        Rails.logger.info "Rule #{rule_set.id} applies to product #{cart_item['variantId']}, creating product..."
        
        if create_partial_product_for_rule(shop, cart_item, cart_hash, session_id, rule_set, overall_cart_value, false)
          products_created += 1
          Rails.logger.info "Successfully created individual rule product #{products_created}"
        else
          Rails.logger.error "Failed to create product for item #{cart_item['variantId']} with individual rule #{rule_set.id}"
        end
      end
    end
    
    Rails.logger.info "Individual rules processing complete: #{products_created} products created"
    products_created
  end

  def self.create_cart_rule_products(shop, cart_details, cart_hash, session_id, cart_rules, overall_cart_value)
    products_created = 0
    
    Rails.logger.info "Processing #{cart_rules.count} cart rules for cart value: #{overall_cart_value}"
    
    cart_rules.each do |cart_rule|
      Rails.logger.info "Checking cart rule #{cart_rule.id} (#{cart_rule.rule_name}): min=#{cart_rule.min_cart_range}, max=#{cart_rule.max_cart_range}"
      
      unless cart_rule_applies?(cart_rule, overall_cart_value)
        Rails.logger.info "Cart rule #{cart_rule.id} does not apply to cart value #{overall_cart_value}"
        next
      end
      
      Rails.logger.info "Cart rule #{cart_rule.id} applies! Creating products for #{cart_details.count} items"
      
      cart_details.each do |cart_item|
        Rails.logger.info "Creating product for item #{cart_item['variantId']} with cart rule #{cart_rule.id}"
        
        if create_partial_product_for_rule(shop, cart_item, cart_hash, session_id, cart_rule, overall_cart_value, true)
          products_created += 1
          Rails.logger.info "Successfully created product #{products_created}"
        else
          Rails.logger.error "Failed to create product for item #{cart_item['variantId']} with cart rule #{cart_rule.id}"
        end
      end
    end
    
    Rails.logger.info "Cart rules processing complete: #{products_created} products created"
    products_created
  end

  def self.create_partial_product_for_rule(shop, cart_item, cart_hash, session_id, rule_set, overall_cart_value, is_cart_rule)
    begin
      Rails.logger.info "Creating partial product: shop=#{shop.id}, variant=#{cart_item['variantId'] || cart_item[:variantId]}, rule=#{rule_set.id} (#{rule_set.rule_name}), is_cart_rule=#{is_cart_rule}"
      
      # Extract variant ID with fallback (handle both underscore and camelCase)
      variant_id = cart_item['variant_id'] || cart_item[:variant_id] ||
                   cart_item['variantId'] || cart_item[:variantId]
      
      # Extract quantity with multiple fallbacks (same logic as find_appropriate_mapping)
      quantity = cart_item['quantity'] || cart_item[:quantity] || 
                 cart_item['totalQuantity'] || cart_item[:totalQuantity] ||
                 cart_item['qty'] || cart_item[:qty]
      
      # Extract cost with fallbacks
      cost = cart_item['cost'] || cart_item[:cost] || 
             cart_item['price'] || cart_item[:price] || 0.0
      cost = cost.to_f
  
      # Validate essential data
      if variant_id.blank?
        Rails.logger.error "Missing variant ID in cart item: #{cart_item.inspect}"
        return false
      end
      
      if quantity.nil? || quantity.to_i <= 0
        Rails.logger.error "Invalid quantity (#{quantity}) in cart item: #{cart_item.inspect}"
        return false
      end
      
      if cost <= 0
        Rails.logger.error "Invalid cost (#{cost}) in cart item: #{cart_item.inspect}"
        return false
      end
      
      quantity = quantity.to_i
      
      Rails.logger.info "Item details: variant_id=#{variant_id}, quantity=#{quantity}, cost=#{cost}"
  
      # Calculate partial amount based on rule
      if is_cart_rule
        multiplier = rule_set.amount_type == 'fixed' ? 
                      (rule_set.amount.to_f / overall_cart_value) : 
                      (rule_set.amount.to_f * 0.01)
        partial_total = (multiplier * cost).round(2)
        Rails.logger.info "Cart rule calculation: amount=#{rule_set.amount}, type=#{rule_set.amount_type}, multiplier=#{multiplier}, partial_total=#{partial_total}"
      else
        multiplier = rule_set.amount_type == 'fixed' ? 1.0 : rule_set.amount.to_f * 0.01
        partial_total = (multiplier * cost).round(2)
        partial_total = rule_set.amount.to_f if rule_set.amount_type == 'fixed'
        Rails.logger.info "Individual rule calculation: amount=#{rule_set.amount}, type=#{rule_set.amount_type}, multiplier=#{multiplier}, partial_total=#{partial_total}"
      end
  
      # Validate calculated partial total
      if partial_total <= 0
        Rails.logger.error "Invalid partial total (#{partial_total}) calculated for rule #{rule_set.id}"
        return false
      end
  
      # Extract title with fallback
      title = cart_item['title'] || cart_item[:title] || "Untitled Product"
      
      partial_title = title.start_with?("Partial Payment for") ?
                        title :
                        "Partial Payment for #{title}"
  
      # Add rule info and unique identifier to make title unique
      timestamp = Time.current.to_i
      random_id = rand(1000)
      partial_title = "#{partial_title} (#{rule_set.rule_name}) #{timestamp}-#{random_id}"
  
      Rails.logger.info "About to call PartialProductCreateService with title: #{partial_title}"
  
      # Create variant with quantity identifier - NOW WITH VALIDATED DATA
      variant_with_quantity = "#{variant_id}:#{quantity}"
      
      Rails.logger.info "Creating variant identifier: #{variant_with_quantity}"
      
      # Extract image URL with fallback
      image_url = cart_item['imageUrl'] || cart_item[:imageUrl] || 
                  cart_item['image_url'] || cart_item[:image_url] || 
                  cart_item['featured_image'] || cart_item[:featuredImage] || 
                  nil
      
      # Call the service with session and cart info - it will create everything properly
      generated_variant_id = call_partial_product_service(
        shop,
        partial_title,
        partial_total,
        [variant_with_quantity],
        image_url,
        cost,
        session_id,
        cart_hash,
        rule_set.id
      )
  
      if generated_variant_id.present?
        Rails.logger.info "✅ Service created variant: #{generated_variant_id} with session: #{session_id}"
        return true
      else
        Rails.logger.error "❌ Service returned empty variant ID"
        return false
      end
  
    rescue => e
      Rails.logger.error "Failed to create product for rule #{rule_set.id}: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join('\n')}"
      Rails.logger.error "Cart item data: #{cart_item.inspect}"
      
      SlackNotifyJob.perform_async(
        ":boom: Individual product creation failed\n🛍️ Shop: #{shop.shopify_domain}\n📦 Item: #{cart_item.inspect}\n🔧 Rule: #{rule_set.rule_name}\n📱 Session: #{session_id}\n💥 Error: #{e.message}"
      )
      return false
    end
  end

  def self.call_partial_product_service(shop, title, price, variant_ids, image_url, original_price, session_id, cart_hash, cart_rule_id)
    begin
      # Try to load and instantiate the service class directly
      require Rails.root.join('app/services/shopify_services/partial_product_create_service')
      
      # Get the class from the loaded file
      service_class = nil
      
      # Try different possible class names
      possible_names = [
        'ShopifyServices::PartialProductCreateService',
        'PartialProductCreateService'
      ]
      
      possible_names.each do |class_name|
        begin
          service_class = class_name.constantize
          Rails.logger.info "✅ Found service class: #{class_name}"
          break
        rescue NameError
          Rails.logger.warn "❌ Class not found: #{class_name}"
          next
        end
      end
      
      unless service_class
        raise StandardError, "Could not find PartialProductCreateService class"
      end
      
      # Call the service with session info
      variant_id = service_class.call(
        shop, 
        title, 
        price, 
        variant_ids, 
        image_url, 
        original_price,
        session_id: session_id,
        cart_hash: cart_hash,
        cart_rule_id: cart_rule_id
      )
      
      Rails.logger.info "✅ Service call successful, variant ID: #{variant_id}"
      variant_id
      
    rescue => e
      Rails.logger.error "Error calling partial product service: #{e.message}"
      
      # Ultimate fallback: create a simple variant ID and mapping manually
      Rails.logger.warn "Falling back to manual product creation"
      create_fallback_mapping(shop, title, price, variant_ids, original_price, session_id, cart_hash, cart_rule_id)
    end
  end

  def self.rule_applies_to_product?(rule_set, cart_item)
    Rails.logger.info "Checking if rule #{rule_set.id} applies to product: is_all=#{rule_set.is_all?}, product_ids=#{rule_set.product_ids}"
    
    if rule_set.is_all?
      Rails.logger.info "Rule applies to all products"
      return true
    end
    
    if rule_set.product_ids.blank?
      Rails.logger.info "Rule has no specific product IDs, not applying"
      return false
    end
    
    # Check if the variant's product is in the rule's product_ids
    # You might need to adjust this logic based on how you store product relationships
    variant_id = cart_item['variantId']
    
    Rails.logger.info "Checking variant #{variant_id} against product_ids: #{rule_set.product_ids}"
    
    # For now, assuming the rule applies since we don't have product mapping logic
    # TODO: Implement proper product ID checking based on your variant->product relationship
    Rails.logger.info "Assuming rule applies (implement proper product checking logic)"
    true
  end

  def self.cart_rule_applies?(cart_rule, cart_value)
    Rails.logger.info "Checking if cart rule #{cart_rule.id} applies: is_cart_rule=#{cart_rule.is_cart_rule?}, cart_value=#{cart_value}"
    
    return false unless cart_rule.is_cart_rule?
    
    # Check cart value ranges
    min_range = cart_rule.min_cart_range || 0
    max_range = cart_rule.max_cart_range
    
    Rails.logger.info "Cart rule ranges: min=#{min_range}, max=#{max_range}"
    
    # If max_range is 0 or nil, treat as unlimited
    if max_range.nil? || max_range == 0
      applies = cart_value >= min_range
      Rails.logger.info "No max limit, applies: #{applies} (#{cart_value} >= #{min_range})"
    else
      applies = cart_value >= min_range && cart_value <= max_range
      Rails.logger.info "With max limit, applies: #{applies} (#{min_range} <= #{cart_value} <= #{max_range})"
    end
    
    applies
  end

  def self.calculate_cart_value(cart_details)
    cart_details.sum do |item|
      # Handle both quantity key formats
      quantity = (item['quantity'] || item[:quantity] || 
                  item['totalQuantity'] || item[:totalQuantity] ||
                  item['qty'] || item[:qty] || 1).to_i
      
      # Handle both cost/price key formats            
      cost = (item['cost'] || item[:cost] || 
              item['price'] || item[:price] || 0.0).to_f
      
      cost * quantity
    end
  end

  def self.create_fallback_mapping(shop, title, price, variant_ids, original_price, session_id, cart_hash, cart_rule_id)
    # Generate a simple variant ID for fallback
    timestamp = Time.current.to_i
    variant_id = "fallback_#{timestamp}_#{rand(1000)}"
    
    Rails.logger.info "Creating fallback mapping with variant ID: #{variant_id}"
    
    # Create a minimal mapping entry with session info
    PartialProductMapping.create!(
      shopify_domain: shop.shopify_domain,
      partial_variant_id: variant_id,
      original_variant_ids: variant_ids,
      original_cost: original_price,
      partial_price: price,
      session_id: session_id,
      cart_hash: cart_hash,
      cart_rule_id: cart_rule_id,
      is_deleted: false
    )
    
    Rails.logger.info "✅ Created fallback mapping for #{variant_ids} with session: #{session_id}"
    variant_id
  end

  # Find the right mapping based on current cart state and session
# Find the right mapping based on current cart state and session
def self.find_appropriate_mapping(shop, cart_item, cart_hash, session_id, requested_rule_id, is_cart_rule)
  # Handle different possible quantity keys and ensure we have a value
  quantity = cart_item['quantity'] || cart_item[:quantity] || 
             cart_item['totalQuantity'] || cart_item[:totalQuantity] ||
             cart_item['qty'] || cart_item[:qty]
  
  if quantity.nil?
    Rails.logger.warn "No quantity found in cart_item, defaulting to 1"
    quantity = 1
  end
  
  # Handle different possible variant ID keys
  variant_id = cart_item['variant_id'] || cart_item[:variant_id] ||
               cart_item['variantId'] || cart_item[:variantId]
  
  if variant_id.nil?
    Rails.logger.error "No variant ID found in cart_item: #{cart_item.inspect}"
    return nil
  end
  
  # Construct the variant_id with quantity to match exactly what's stored
  variant_with_quantity = "#{variant_id}:#{quantity}"
  
  Rails.logger.info "DEBUG searching for EXACT match: #{variant_with_quantity} with cart_hash: #{cart_hash}"
  
  # ONLY exact match - must include variant_id:quantity, cart_hash, session_id, and rule
  exact_query = PartialProductMapping.where(
    shopify_domain: shop.shopify_domain,
    cart_hash: cart_hash,
    session_id: session_id,
    is_deleted: false
  ).where("original_variant_ids::text LIKE ?", "%#{variant_with_quantity}%")

  if requested_rule_id.present?
    if is_cart_rule
      exact_query = exact_query.joins("LEFT JOIN partial_rule_sets ON partial_rule_sets.id = partial_product_mappings.cart_rule_id")
                               .where(cart_rule_id: requested_rule_id)
                               .where('partial_rule_sets.is_cart_rule = ?', true)
    else
      exact_query = exact_query.joins("LEFT JOIN partial_rule_sets ON partial_rule_sets.id = partial_product_mappings.cart_rule_id")
                               .where(cart_rule_id: requested_rule_id)
                               .where('partial_rule_sets.is_cart_rule = ?', false)
    end
  end

  result = exact_query.first
  
  if result
    Rails.logger.info "DEBUG exact match found: #{result.inspect}"
  else
    Rails.logger.info "DEBUG no exact match found for: #{variant_with_quantity} with cart_hash: #{cart_hash}"
    Rails.logger.info "This will trigger fallback product creation since no exact mapping exists"
  end
  
  result
end
end