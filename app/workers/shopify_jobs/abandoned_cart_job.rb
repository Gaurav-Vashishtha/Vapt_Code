module ShopifyJobs
  class AbandonedCartJob < ApplicationJob  
    def perform(shop_id, db_abandon_cart_id)
      puts '📦 Abandoned job started'

      db_abandon_cart = AbandonedCart.find_by(id: db_abandon_cart_id)
      return unless db_abandon_cart&.checkout_id

      # ✅ Skip if already marked as recovered
      if db_abandon_cart.notes.to_s.downcase.strip == 'recovered'
        puts "✅ Skipping — already marked as Recovered"
        return
      end

      if !db_abandon_cart.sid.blank? || db_abandon_cart.status=='SUCCESS' || db_abandon_cart.status=='IN_PROGRESS'
        puts "✅ Skipping — already sent"
        return
      end

      db_abandon_cart.update(status:'IN_PROGRESS')

      shop = Shop.find_by(id: shop_id)
      return if shop.blank? || shop.setting&.locked

      # 🔍 Skip PreOrderOtp carts that are already ordered
      if uuid_format?(db_abandon_cart.checkout_id)
        pre_order_otp = PreOrderOtp.find_by(device_id: db_abandon_cart.checkout_id)

        if pre_order_otp.present? && pre_order_otp.order_status == 'ORDER_PLACED'
          puts "✅ Skipping — PreOrderOtp already ORDER_PLACED: #{pre_order_otp.id}"
          return
        end
      end

      # 📤 Handle based on notification type
      case db_abandon_cart.notif_type
      when 'SMS'
        NetworkServices::AbandonedSendSmsService.call(
          db_abandon_cart.id,
          shop.setting.abandoned_template,
          '',
          true
        )

      when 'WHATSAPP'
        # Suppress the abandoned-cart WhatsApp when this number already placed an
        # order within the merchant's configured window. `omit_whatsapp_message_ttl`
        # is in minutes; 0 (default) disables the check (other merchants unaffected).
        ttl = shop.setting&.omit_whatsapp_message_ttl.to_i
        if ttl > 0 && recent_order_for_phone?(shop, db_abandon_cart.phone, ttl)
          puts "✅ Skipping — recent order within #{ttl}m for #{db_abandon_cart.phone}"
          return
        end

        if db_abandon_cart.dynamic_config.present?
          puts "🧠 Using DynamicAbandonedCartWhatsappService"
          NetworkServices::DynamicAbandonedCartWhatsappService.call(shop, db_abandon_cart)

        elsif shop.setting.ac_whatsapp_discout_enabled &&
              shop.setting.ac_whatsapp_discount.present? &&
              shop.setting.ac_whatsapp_discount_code.present?

          puts "💸 Using WhatsappAbandonDiscountService"
          NetworkServices::WhatsappAbandonDiscountService.call(shop, db_abandon_cart)

        else
          puts "📨 Using Default WhatsappAbandonService"
          NetworkServices::WhatsappAbandonService.call(shop, db_abandon_cart)
        end

      else
        puts "⚠️ Invalid Notif type: #{db_abandon_cart.notif_type}"
      end
    end

    private

    # True when an order was placed with this phone for the shop within the last
    # `ttl_minutes`. Matches on the trailing 10 national digits to tolerate the
    # mix of stored phone formats (+91…, 91…, bare 10-digit). Counts both
    # confirmed OrderConfirmations and OTP rows marked ORDER_PLACED.
    def recent_order_for_phone?(shop, phone, ttl_minutes)
      national = phone.to_s.gsub(/\D/, '').last(10)
      return false if national.blank?
      cutoff = ttl_minutes.to_i.minutes.ago

      return true if OrderConfirmation
        .where(shop_id: shop.id)
        .where('created_at > ?', cutoff)
        .where("right(regexp_replace(coalesce(customer_number, ''), '\\D', '', 'g'), 10) = ?", national)
        .exists?

      PreOrderOtp
        .where(shop_id: shop.id, order_status: 'ORDER_PLACED')
        .where('created_at > ?', cutoff)
        .where("right(regexp_replace(coalesce(phone, ''), '\\D', '', 'g'), 10) = ?", national)
        .exists?
    end

    def uuid_format?(str)
      str.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end
  end
end
