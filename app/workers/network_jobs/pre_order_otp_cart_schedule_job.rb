module NetworkJobs
  class PreOrderOtpCartScheduleJob < ApplicationJob
    LOOKBACK_WINDOW = 1.day.freeze 
    MAX_CART_AGE = 24.hours.freeze # Don't process very old carts
    
    def perform(shop_id = nil)
      puts "📦 PreOrderOtpCartScheduleJob started"

      settings = if shop_id.present?
                   setting = Setting.find_by(shop_id: shop_id)
                   setting.present? ? [setting] : []
                 else
                   Setting.where(abandoned_cart_enabled: true)
                          .or(Setting.where(ac_whatsapp: true))
                 end

      settings.each do |setting|
        shop = setting.shop
        next if shop.blank?

        begin
          # Whatsapp::ScheduleAbandonedCartRemindersJob covers both Shopify
          # checkouts and pre-order OTPs for BSP shops; running both would send
          # two reminders per cart.
          if shop.bsp_abandoned_cart?
            Rails.logger.info("[otp_cart_schedule] shop=#{shop.id} on BSP abandoned cart — skipping MSG91 path")
            next
          end

          shop.init_session
          shop_domain = shop.shopify_domain

          sms_schedules = setting.ac_sms_schedule.to_s.split(',').select { |n| n.to_i >= 0 }
          whatsapp_schedules = setting.ac_whatsapp_schedule.to_s.split(',').select { |n| n.to_i >= 0 }

          # OPTIMIZATION: Only fetch records that haven't been scheduled yet
          # Use a LEFT JOIN to find PreOrderOtp records without corresponding ac_schedules
          pre_order_otps = PreOrderOtp.joins(
            "LEFT JOIN abandon_cart_schedules acs ON acs.cart_id = CAST(pre_order_otps.device_id AS TEXT) AND acs.shop_id = #{shop.id}"
          ).where(
            shop_id: shop.id,
            order_status: 'AbandonedCheckout'
          ).where("cart_details IS NOT NULL")
           .where("pre_order_otps.created_at >= ?", LOOKBACK_WINDOW.ago)
           .where("pre_order_otps.created_at >= ?", MAX_CART_AGE.ago)  # Also filter out old carts in query
           .where("acs.id IS NULL OR acs.is_sheduled IS NULL OR acs.is_sheduled = false")  # Only unscheduled ones

          puts "🔍 Found #{pre_order_otps.count} unscheduled pre-order OTPs for shop #{shop_domain}"

          pre_order_otps.find_each(batch_size: 100) do |otp|  # Use find_each for memory efficiency
            begin
              # Skip if cart_details is empty or all blank
              next if otp.cart_details.blank? || otp.cart_details.reject(&:blank?).empty?

              cart_id = otp.device_id.to_s
              
              # Double-check with lock to prevent race conditions (this should be rare now)
              ac_schedule = shop.abandon_cart_schedules.lock.find_or_initialize_by(cart_id: cart_id)
              not_scheduled_before = ac_schedule.is_sheduled.blank? || !ac_schedule.is_sheduled

              next unless not_scheduled_before

              # Build cart permalink
              line_items_string = PreOrderOtpCart.line_items(otp.cart_details).map { |li| "#{li[:variant_id]}:#{li[:quantity]}" }
              first_featured_image = otp.cart_details.find { |item| item["featured_image"].present? }&.dig("featured_image")

              next if line_items_string.empty?

              permalink = "https://#{shop_domain}/cart/#{line_items_string.join(',')}?storefront=true&_codkSessionId=#{otp.device_id}"
              puts "🛒 Cart URL: #{permalink}"

              product_info = otp.cart_details.map { |i| 
                title = i["title"] || ""
                
                # Remove both "Partial Payment for" and "Partial Payment :" patterns
                title = title.gsub(/Partial Payment for\s*/i, '') if title.include?("Partial Payment for")
                title = title.gsub(/\s*-\s*Partial Payment\s*:\s*/i, '') if title.include?("Partial Payment :")
                
                # Clean up any remaining "Partial Payment" patterns and extra spaces/dashes
                title = title.gsub(/\s*-?\s*Partial Payment\s*:?\s*/i, '')
                title = title.strip.gsub(/\s*-\s*$/, '') # Remove trailing dash and spaces
                
                "#{title} : Qty:#{i["quantity"]}" 
              }.join(", ")
              
              customers = Customer.where(phone: otp.phone)
              name = "Customer"
              
              if customers.any?
                first_name = customers.first.first_name.to_s.strip
                last_name = customers.first.last_name.to_s.strip
              
                if first_name.present? && last_name.present?
                  name = "#{first_name} #{last_name}"
                elsif first_name.present?
                  name = first_name
                elsif last_name.present?
                  name = last_name
                end
              end
              
              customer_phone = otp.phone
              country_code = otp.country_code
              total_price = otp.cart_details.sum { |i| i["price"].to_f * i["quantity"].to_i }

              valid_input = customer_phone.present? && country_code.present?
              success_count = 0

              # Use transaction to ensure atomicity
              ActiveRecord::Base.transaction do
                # Schedule SMS
                if setting.abandoned_cart_enabled && sms_schedules.any? && valid_input
                  sms_schedules.each do |delay|
                    # Calculate intended time based on cart creation, not current time
                    intended_time = otp.created_at + delay.to_i.minutes
                    
                    # Skip if the intended time has already passed
                    # next if intended_time < DateTime.now
                    
                    # Check if notification already exists for this exact time
                    existing_sms = shop.abandoned_carts.where(
                      checkout_id: cart_id,
                      notif_type: 'SMS',
                      scheduled_at: intended_time
                    ).exists?
                    
                    next if existing_sms
                    
                    db_abandon_cart = shop.abandoned_carts.new(
                      checkout_id: cart_id,
                      url: permalink,
                      shopify_created_at: otp.created_at,
                      phone: customer_phone,
                      country_code: country_code,
                      notif_type: 'SMS',
                      total_price: total_price,
                      name: name,
                      scheduled_at: intended_time, # Fixed: Use cart creation time + delay
                      shop_id: shop.id,
                      featured_image: first_featured_image
                    )

                    if db_abandon_cart.save
                      begin
                        ShopifyJobs::AbandonedCartJob.perform_in(delay.to_i.minutes, shop.id, db_abandon_cart.id)
                        ac_schedule.increment(:schedule_count)
                        success_count += 1
                      rescue => e
                        # If job scheduling fails, remove the DB record to maintain consistency
                        db_abandon_cart.destroy
                        puts "❌ Failed to schedule SMS job for OTP #{otp.id}: #{e.message}"
                      end
                    end
                  end
                end

                # Schedule WhatsApp
                if setting.ac_whatsapp && whatsapp_schedules.any? && valid_input
                  whatsapp_schedules.each_with_index do |delay, index|
                    # Calculate intended time based on cart creation, not current time
                    intended_time = otp.created_at + delay.to_i.minutes
                    
                    # Skip if the intended time has already passed
                    # next if intended_time < DateTime.now
                    
                    # Check if notification already exists for this exact time
                    existing_whatsapp = shop.abandoned_carts.where(
                      checkout_id: cart_id,
                      notif_type: 'WHATSAPP',
                      scheduled_at: intended_time
                    ).exists?
                    
                    next if existing_whatsapp
                    
                    dynamic_config = setting.abandoned_cart_configs&.[](index)
                    
                    db_abandon_cart = shop.abandoned_carts.new(
                      checkout_id: cart_id,
                      url: permalink,
                      shopify_created_at: otp.created_at,
                      phone: customer_phone,
                      country_code: country_code,
                      notif_type: 'WHATSAPP',
                      total_price: total_price,
                      name: name,
                      scheduled_at: intended_time, # Fixed: Use cart creation time + delay
                      shop_id: shop.id,
                      dynamic_config: dynamic_config,
                      featured_image: first_featured_image
                    )

                    if db_abandon_cart.save
                      begin
                        ShopifyJobs::AbandonedCartJob.perform_in(delay.to_i.minutes, shop.id, db_abandon_cart.id)
                        ac_schedule.increment(:schedule_count)
                        success_count += 1
                      rescue => e
                        # If job scheduling fails, remove the DB record to maintain consistency
                        db_abandon_cart.destroy
                        puts "❌ Failed to schedule WhatsApp job for OTP #{otp.id}: #{e.message}"
                      end
                    end
                  end
                end

                # Only mark as scheduled if we successfully scheduled at least one notification
                if success_count > 0
                  ac_schedule.update!(
                    product_info: product_info,
                    is_sheduled: true
                  )
                end
              end

              puts "✅ OTP #{otp.id} scheduled with #{success_count} notifications"

            rescue => e
              puts "❌ Error processing OTP ID #{otp.id} for shop #{shop_domain}: #{e.message}"
              # Don't mark as scheduled if there was an error
            end
          end

        rescue => e
          puts "❌ Error in shop #{shop.shopify_domain}: #{e.message}"
        end
      end

      puts "✅ PreOrderOtpCartScheduleJob completed"
    end
  end
end