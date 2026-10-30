module NetworkJobs
  class AbandonedCartScheduleJob < ApplicationJob  
    
    # NetworkJobs::AbandonedCartScheduleJob.perform_async

    PARTIAL_PAYMENT_PLACEHOLDER_TITLE = "Partial Payment".freeze
    PARENT_VARIANT_PROPERTY = "_parentVariantId".freeze
    PARENT_PRODUCT_TITLE_PROPERTY = "_productTitle".freeze

    # Get checkout URL
    GOKWIK_SHOPS = [
      'funkykids-7504.myshopify.com',
      'rangraze.myshopify.com'
      # Add more GoKwik shops here as needed
      # 'another-gokwik-shop.myshopify.com',
      # 'third-gokwik-shop.myshopify.com'
    ].freeze
    
    RAZORPAY_SHOPS = [
      'ipurchasesmartly.myshopify.com',
      'ice7u1-ma.myshopify.com'
      # Add more iPurchaseSmartly shops here if needed
      # 'another-ipurchase-shop.myshopify.com'
    ].freeze

    def clean_phone_number(phone, country_code)
      if !phone.blank?
        phone = phone.tr('^0-9', '').sub!(/^0*/, '')
      end
      phone = Phonelib.parse(phone, country_code).to_s
      if !country_code.blank? && country_code.downcase == 'ae'
        if phone.length<=9
          phone = '+971' + phone
        elsif (phone.length == 12) && (!phone.start_with? '+')
          phone= '+' + phone
        end
      end
      return phone
    rescue Exception => e
      SlackNotifyJob.perform_async(
        ":rage:  (#{Rails.env})\n *Error* Phonelib parse \n Phone: #{phone}  \n country_code: #{country_code} \n error: #{e.message}"
      )
      phone
    end

    def partial_payment_placeholder_title?(title)
      title.to_s.strip.casecmp?(PARTIAL_PAYMENT_PLACEHOLDER_TITLE)
    end

    # Admin line items may differ between `title` (product) and `presentment_title`; treat either as the placeholder.
    def partial_payment_line_item?(line_item)
      partial_payment_placeholder_title?(line_item&.title) ||
        partial_payment_placeholder_title?(line_item&.presentment_title)
    end

    def line_item_property_key(p)
      if p.respond_to?(:name) && p.name.present?
        p.name.to_s
      elsif p.respond_to?(:key) && p.key.present?
        p.key.to_s
      else
        (p["name"] || p[:name] || p["key"] || p[:key]).to_s
      end
    end

    def line_item_property_value(line_item, name)
      props = line_item.properties
      return nil if props.blank?

      props.each do |p|
        key = line_item_property_key(p)
        next if key.blank? || key != name.to_s
        val = p.respond_to?(:value) ? p.value : p["value"] || p[:value]
        return val.to_s.presence
      end
      nil
    end

    def normalize_variant_gid(gid)
      s = gid.to_s.strip
      return s if s.start_with?("gid://shopify/ProductVariant/")
      return "gid://shopify/ProductVariant/#{s}" if s.match?(/\A\d+\z/)

      s
    end

    def variant_numeric_id_from_gid(gid)
      normalized = normalize_variant_gid(gid)
      m = normalized.match(%r{/ProductVariant/(\d+)\z})
      m ? m[1] : nil
    end

    def product_legacy_id_for_variant_gid(shop, variant_gid)
      vid = normalize_variant_gid(variant_gid)
      return nil if vid.blank? || !vid.start_with?("gid://shopify/ProductVariant/")

      client = shop.with_shopify_session { ShopifyAPI::GraphQL.client }
      query = client.parse <<-'GRAPHQL'
        query($id: ID!) {
          productVariant(id: $id) {
            product {
              legacyResourceId
            }
          }
        }
      GRAPHQL

      response = client.query(query, variables: { id: vid })
      legacy = response&.data&.product_variant&.product&.legacy_resource_id
      legacy.present? ? legacy.to_s : nil
    rescue Exception => e
      puts "Error resolving product for variant #{vid}: #{e.message}"
      nil
    end

    # Fallback when `_productTitle` is missing but `_parentVariantId` is set (GraphQL).
    def variant_display_label_for_cart_line(shop, variant_gid)
      vid = normalize_variant_gid(variant_gid)
      return nil if vid.blank? || !vid.start_with?("gid://shopify/ProductVariant/")

      client = shop.with_shopify_session { ShopifyAPI::GraphQL.client }
      query = client.parse <<-'GRAPHQL'
        query($id: ID!) {
          productVariant(id: $id) {
            displayName
            title
            product {
              title
            }
          }
        }
      GRAPHQL

      response = client.query(query, variables: { id: vid })
      pv = response&.data&.product_variant
      return nil if pv.blank?

      variant_part = pv.title.to_s.strip
      variant_part = nil if variant_part.blank? || variant_part == "Default Title"

      pv.display_name.presence ||
        [pv.product&.title, variant_part].compact.join(" — ").presence
    rescue Exception => e
      puts "Error resolving variant label for #{vid}: #{e.message}"
      nil
    end

    def get_variant_ids_by_title(shop, product_title)
      client = shop.with_shopify_session { ShopifyAPI::GraphQL.client }

      query = client.parse <<-'GRAPHQL'
        query($query: String!) {
          products(first: 1, query: $query) {
            edges {
              node {
                id
                title
                variants(first: 50) {
                  edges {
                    node {
                      id
                      title
                      sku
                    }
                  }
                }
              }
            }
          }
        }
      GRAPHQL

      variables = { query: "title:#{product_title}" }
      response = client.query(query, variables: variables)

      if response&.data&.products&.edges&.any?
        product_node = response.data.products.edges.first.node
        puts "🛍️ Product: #{product_node.title}"

        product_node.variants.edges.map do |edge|
          {
            id: edge.node.id.gsub("gid://shopify/ProductVariant/", ""),
            title: edge.node.title,
            sku: edge.node.sku
          }
        end
      else
        puts "❌ No product found with title: #{product_title}"
        []
      end
    end

    def get_product_image_url(shop, product_id)
      return nil if product_id.blank?
      
      ShopifyServices::ProductImageService.call(shop, product_id)
    rescue Exception => e
      puts "Error fetching product image: #{e.message}"
      nil
    end

    def get_product_info(abandoned_cart, shop)
      product_info = ''

      abandoned_cart.line_items.each do |line_item|
        presentment = line_item.presentment_title.to_s
        cleaned_title =
          if partial_payment_line_item?(line_item)
            from_prop = line_item_property_value(line_item, PARENT_PRODUCT_TITLE_PROPERTY).presence
            parent_gid = line_item_property_value(line_item, PARENT_VARIANT_PROPERTY)
            from_prop ||
              (shop && parent_gid.present? ? variant_display_label_for_cart_line(shop, parent_gid) : nil) ||
              presentment.presence ||
              line_item.title.to_s
          elsif presentment.include?("Partial Payment for")
            presentment.sub("Partial Payment for", "").strip
          else
            presentment.presence || line_item.title.to_s
          end

        product_info += "#{cleaned_title} : Qty:#{line_item.quantity},"
      end

      product_info = product_info.chop unless product_info.blank?
      product_info
    end
    
    def generate_cart_permalink_from_cart(shop, abandoned_cart)
      shop_domain = shop.shopify_domain
      line_items_string = []
    
      abandoned_cart.line_items.each do |line_item|
        title = line_item.title.to_s.strip
        quantity = line_item.quantity

        if title.include?("Partial Payment for")
          # Extract product title and variant
          cleaned_title = title.sub("Partial Payment for", "").strip
          base_title, variant_title = cleaned_title.split(' - ', 2).map(&:strip)
    
          if base_title.blank? || variant_title.blank?
            puts "⚠️ Unable to extract base or variant from: #{cleaned_title}"
            next
          end
    
          variants = get_variant_ids_by_title(shop, base_title)
          matched = variants.find { |v| v[:title].strip == variant_title }
    
          if matched
            line_items_string << "#{matched[:id]}:#{quantity}"
          else
            puts "❌ No match for '#{base_title}' with variant: '#{variant_title}'"
          end
        elsif partial_payment_line_item?(line_item)
          parent_gid = line_item_property_value(line_item, PARENT_VARIANT_PROPERTY)
          parent_variant_id = variant_numeric_id_from_gid(parent_gid) if parent_gid.present?

          if parent_variant_id.present?
            line_items_string << "#{parent_variant_id}:#{quantity}"
          elsif line_item.variant_id.present?
            puts "Missing #{PARENT_VARIANT_PROPERTY} for Partial Payment line; using line item variant_id"
            line_items_string << "#{line_item.variant_id}:#{quantity}"
          else
            puts "Partial Payment line missing #{PARENT_VARIANT_PROPERTY} and variant_id: #{title.presence || line_item.presentment_title}"
          end
        else
          # Fallback: Use variant_id from line item directly
          if line_item.variant_id.present?
            line_items_string << "#{line_item.variant_id}:#{quantity}"
          else
            puts "⚠️ Missing variant_id for line item: #{title}"
          end
        end
      end

      if line_items_string.any?
        permalink = "https://#{shop_domain}/cart/#{line_items_string.join(',')}?storefront=true"
        puts "🛒 Final Cart Permalink: #{permalink}"
        return permalink
      else
        puts "⚠️ No valid line items found for permalink."
        return nil
      end
    end
    
        
    def perform
      puts 'Abandoned Cart Schedule job started'
      settings = Setting.where('abandoned_cart_enabled':true).or(Setting.where('ac_whatsapp':true))
      messages = []
      success_count = 0
      
      settings.each do |setting|
        begin
          # Whatsapp::ScheduleAbandonedCartRemindersJob owns BSP shops; running
          # both would send two WhatsApp messages per stage.
          if setting.shop.bsp_abandoned_cart?
            Rails.logger.info("[ac_schedule] shop=#{setting.shop_id} on BSP abandoned cart — skipping MSG91 path")
            next
          end

          # Webhook-ingested shops get their stages scheduled at ingest by
          # Webhooks::ProcessInboundEventJob, and their carts never appear in
          # Shopify's abandonedCheckouts anyway.
          if setting.shop.webhook_cart_ingestion?
            Rails.logger.info("[ac_schedule] shop=#{setting.shop_id} on webhook ingestion — skipping Shopify poll")
            next
          end

          setting.shop.init_session
          min_created = (Time.zone&.today || Date.current).beginning_of_day
          abandoned_carts = ShopifyServices::AbandonedCheckoutGraphqlFetcher.fetch_created_since(setting.shop, min_created)

          error_count = 0
          report_text =''

          abandoned_carts.each do |abandoned_cart|
            begin
              # Use database lock to prevent race conditions
              ac_schedule = setting.shop.abandon_cart_schedules.lock.find_or_initialize_by(cart_id: abandoned_cart.id)
              
              # Skip if already scheduled
              not_scheduled_before = ac_schedule.is_sheduled.blank? || !ac_schedule.is_sheduled
              next unless not_scheduled_before

              sms_schedules = setting.ac_sms_schedule.split(',').select { |number| number.to_i >= 0 }
              whatsapp_schedules = setting.ac_whatsapp_schedule.split(',').select { |number| number.to_i >= 0 }
              
              country_code = ''
              customer_phone = abandoned_cart&.phone || abandoned_cart&.shipping_address&.phone || abandoned_cart&.billing_address&.phone 
              product_info = get_product_info(abandoned_cart, setting.shop)
              
              # Get featured image URL from first line item (real product when line is a Partial Payment placeholder)
              featured_image = ''
              if abandoned_cart.line_items.any?
                first_li = abandoned_cart.line_items.first
                image_product_id =
                  if partial_payment_line_item?(first_li)
                    gid = line_item_property_value(first_li, PARENT_VARIANT_PROPERTY)
                    gid.present? ? product_legacy_id_for_variant_gid(setting.shop, gid) : nil
                  end
                image_product_id ||= first_li.product_id if first_li.product_id.present?
                featured_image = get_product_image_url(setting.shop, image_product_id) || '' if image_product_id.present?
              end
              
              name = ''
              if !abandoned_cart.customer.blank?
                name = abandoned_cart.customer && abandoned_cart.customer.first_name
              end
              if name.blank?
                name = 'Customer'
              end
              if customer_phone.blank? && !abandoned_cart.shipping_address.blank?
                customer_phone = abandoned_cart.shipping_address.phone
              end
              if country_code.blank? && !abandoned_cart.shipping_address.blank?
                country_code = abandoned_cart.shipping_address.country_code
              end

              if country_code.blank?
                begin
                  if customer_phone.present?
                    parsed_phone = Phonelib.parse(customer_phone)
                    if parsed_phone.valid?
                      country_code = parsed_phone.country
                    else
                      country_code = ''
                    end
                  else
                    country_code = ''
                  end
                rescue StandardError => e
                  Rails.logger.error "Error parsing phone number '#{customer_phone}': #{e.message}"
                  country_code = ''
                end
              end
              
              total_price = 0.0
              if !abandoned_cart.total_price.blank?
                total_price = abandoned_cart.total_price.to_f
              end
              
              customer_phone = clean_phone_number(customer_phone, country_code)
              
              if ac_schedule.id.blank?
                ac_schedule.update(schedule_count: 0, product_info: product_info)
              end
              ac_schedule.save
              
              valid_input = (!customer_phone.blank?) && (!country_code.blank?)
              schedule_count = 0
            
              # Main logic
              ac_checkout_url = abandoned_cart.abandoned_checkout_url
              
              if RAZORPAY_SHOPS.include?(setting.shop.shopify_domain)
                if abandoned_cart&.note_attributes&.first
                  ac_checkout_url = abandoned_cart.note_attributes[0].value
                end
              elsif GOKWIK_SHOPS.include?(setting.shop.shopify_domain)
                if abandoned_cart&.note
                  ac_checkout_url = abandoned_cart.note
                end
              elsif setting.partial_payment_enabled
                ac_checkout_url = generate_cart_permalink_from_cart(setting.shop, abandoned_cart)
              end

              # Use transaction to ensure atomicity
              ActiveRecord::Base.transaction do
                # Schedule SMS
                if !sms_schedules.blank? && sms_schedules.size > 0 && setting.abandoned_cart_enabled && valid_input
                  sms_schedules.each do |sms_schedule|
                    # FIXED: Use cart creation time instead of current time
                    intended_time = DateTime.parse(abandoned_cart.created_at) + sms_schedule.to_i.minutes
                    
                    # Skip if intended time has passed
                    next if intended_time < DateTime.now - 30
                    
                    # FIXED: Check for existing notification to prevent duplicates
                    existing_sms = setting.shop.abandoned_carts.where(
                      checkout_id: abandoned_cart.id,
                      notif_type: 'SMS',
                      scheduled_at: intended_time
                    ).exists?
                    
                    next if existing_sms
                    
                    db_abandon_cart = setting.shop.abandoned_carts.new(
                      checkout_id: abandoned_cart.id,
                      url: ac_checkout_url,
                      shopify_created_at: abandoned_cart.created_at,
                      phone: customer_phone,
                      country_code: country_code,
                      notif_type: 'SMS',
                      total_price: total_price,
                      name: name,
                      scheduled_at: intended_time, # FIXED: Use intended time
                      shop_id: setting.shop.id,
                      featured_image: featured_image
                    )
                    
                    if db_abandon_cart.save
                      begin
                        ShopifyJobs::AbandonedCartJob.perform_in(sms_schedule.to_i.minutes, setting.shop.id, db_abandon_cart.id)
                        ac_schedule.increment(:schedule_count)
                        success_count += 1
                      rescue => e
                        # If job scheduling fails, remove the DB record
                        db_abandon_cart.destroy
                        puts "❌ Failed to schedule SMS job: #{e.message}"
                      end
                    end
                  end
                end
                
                # Schedule WhatsApp
                if !whatsapp_schedules.blank? && whatsapp_schedules.size > 0 && setting.ac_whatsapp && valid_input
                  whatsapp_schedules.each_with_index do |whatsapp_schedule, index|
                    # FIXED: Use cart creation time instead of current time
                    intended_time = DateTime.parse(abandoned_cart.created_at) + whatsapp_schedule.to_i.minutes
                    
                    # Skip if intended time has passed
                    next if intended_time < DateTime.now - 30
                    
                    # FIXED: Check for existing notification to prevent duplicates
                    existing_whatsapp = setting.shop.abandoned_carts.where(
                      checkout_id: abandoned_cart.id,
                      notif_type: 'WHATSAPP',
                      scheduled_at: intended_time
                    ).exists?
                    
                    next if existing_whatsapp
                    
                    dynamic_config = setting.abandoned_cart_configs&.[](index)
                  
                    db_abandon_cart = setting.shop.abandoned_carts.new(
                      checkout_id: abandoned_cart.id,
                      url: ac_checkout_url,
                      shopify_created_at: abandoned_cart.created_at,
                      phone: customer_phone,
                      country_code: country_code,
                      notif_type: 'WHATSAPP',
                      total_price: total_price,
                      name: name,
                      scheduled_at: intended_time, # FIXED: Use intended time
                      shop_id: setting.shop.id,
                      dynamic_config: dynamic_config,
                      featured_image: featured_image
                    )
                  
                    if db_abandon_cart.save
                      begin
                        ShopifyJobs::AbandonedCartJob.perform_in(whatsapp_schedule.to_i.minutes, setting.shop.id, db_abandon_cart.id)
                        ac_schedule.increment(:schedule_count)
                        success_count += 1
                      rescue => e
                        # If job scheduling fails, remove the DB record
                        db_abandon_cart.destroy
                        puts "❌ Failed to schedule WhatsApp job: #{e.message}"
                      end
                    end
                  end
                end
                
                # FIXED: Only mark as scheduled if we actually scheduled something
                if schedule_count > 0 || (sms_schedules.empty? && whatsapp_schedules.empty?)
                  ac_schedule.update!(is_sheduled: true)
                end
              end
              
            rescue => e
              messages.push("Error - Phone: #{customer_phone} country_code: #{country_code} shop: #{setting.shop.shopify_domain} error: #{e.message}")
              # Don't mark as scheduled if there was an error
            end
          end
        rescue => e
          if !setting.shop.blank?
            messages.push("Error - shop: #{setting.shop.shopify_domain} error: #{e.message}")
          end
        end
      end
      
      messages.push("Success count #{success_count}")
      message_text = messages.join('\n')
      puts 'Abandoned cart job completed'
    end
  end
end
