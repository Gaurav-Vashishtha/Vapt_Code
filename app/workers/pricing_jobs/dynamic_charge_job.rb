require 'money/bank/open_exchange_rates_bank'

module PricingJobs
  class DynamicChargeJob < ApplicationJob
    sidekiq_options queue: "administration"

    DEFAULT_SMS_CHARGE = 0.02
    DEFAULT_IVR_CHARGE = 0.04
    MINIMUM_ORDER_CHARGE = 0.5
    CAPPED_AMOUNT_THRESHOLD = 50
    MAX_CHARGE_PER_RUN = 300.0
    BATCH_SIZE = 50 # Process shops in batches

    # shop_id_min / shop_id_max: optional inclusive range (used by DynamicChargeCoordinatorJob shards).
    # skip_slack: when true, omit Slack pings (coordinator posts a single schedule summary).
    def perform(shop_id_min = nil, shop_id_max = nil, skip_slack = false)
      @skip_slack_notifications = skip_slack
      rates_source = ExchangeRateBank.install!
      if rates_source != :live && !@skip_slack_notifications
        SlackNotifier::CLIENT.ping(
          text: "DynamicChargeJob (#{Rails.env}): Open Exchange Rates unavailable, using #{rates_source} fallback rates"
        )
      end

      total_charge_across_shops = 0.0
      pricings = TwilioPricing.all.index_by(&:country_code)
      # Support-team WhatsApp multipliers (/admin/shop_charge_overrides); a small table, read once.
      @charge_overrides = MessagePricing.load_charge_overrides
      pricer = MessagePricing.new(pricings: pricings, charge_overrides: @charge_overrides)
      # .includes is a no-op for .count and forces a useless join planning step.
      not_activated = Shop.where(charge_id: nil).count
      success_usage_charges = []
      error_usage_charges = []
      below_threshold_shops = []
      capped_out_shops = []

      # /codk-ops ledger. A deploy can kill this job at any point, so nothing is held until the end:
      # every created charge is written the moment Shopify accepts it, and the per-run counters are
      # flushed after each shop batch and in `ensure`. Never raises (see Ops::DynamicChargeLedger).
      Ops::DynamicChargeLedger.record!(runs: 1)
      ledger_flushed = { failures: 0, capped: 0, below_threshold: 0 }
      flush_ledger_counters = lambda do
        pending = {
          failures: error_usage_charges.size - ledger_flushed[:failures],
          capped: capped_out_shops.size - ledger_flushed[:capped],
          below_threshold: below_threshold_shops.size - ledger_flushed[:below_threshold]
        }
        next if pending.values.all?(&:zero?)

        Ops::DynamicChargeLedger.record!(**pending)
        ledger_flushed[:failures] += pending[:failures]
        ledger_flushed[:capped] += pending[:capped]
        ledger_flushed[:below_threshold] += pending[:below_threshold]
      end

      total_sms = 0
      total_whatsapp = 0
      total_whatsapp_bsp = 0
      total_preorder = 0
      total_abandoned_sms = 0
      total_abandoned_whatsapp = 0
      total_ivr = 0
      total_prepaid = 0
      total_partial_payment = 0

      shops = Shop.joins(:setting)
                  .where(settings: { provider: [nil, ""] })
                  .where.not(charge_id: [nil, ""])
                  .or(Shop.where(shopify_domain: 'praha-chic.myshopify.com').joins(:setting))
                  .order(:id)

      if shop_id_min.present? && shop_id_max.present?
        shops = shops.where(id: shop_id_min.to_i..shop_id_max.to_i)
      end

      # Process shops in batches
      shops.find_in_batches(batch_size: BATCH_SIZE) do |shop_batch|
        shop_batch.each do |shop|
          next if ENV.fetch("OFFLINE_PAYMENTS_ID", nil).to_s.split(',').map(&:to_i).include?(shop.id)

          if shop.setting.blank?
            next
          end

          sms_orders = TwilioLog.where(shop_id: shop.id, is_charged: false, ver_type: ["SMS", "Confirmation-SMS", "Fulfilment-SMS"], status: "SUCCESS")
          ivr_orders = TwilioLog.where(shop_id: shop.id, is_charged: false, ver_type: "IVR", status: "SUCCESS").where.not(status: "Non-COD")
          whatsapp_orders = TwilioLog.where(shop_id: shop.id, is_charged: false, ver_type: ["WHATSAPP", "WHATSAPP_FIRST_PURCHASE", "WHATSAPP-CONFIRMATION", "WHATSAPP-FULFILMENT","WHATSAPP_COD_PREPAID"], status: "SUCCESS")
          # BSP WhatsApp logs — merchant's own WABA, billed per Meta-accepted send.
          whatsapp_bsp_orders = WhatsappMessageLog.where(shop_id: shop.id).chargeable
          abandoned_orders = AbandonedCart.where(shop_id: shop.id, is_charged: nil, status: "SUCCESS", notif_type: 'SMS')
          abandoned_orders_whatsapp = AbandonedCart.where(shop_id: shop.id, is_charged: nil, status: "SUCCESS", notif_type: 'WHATSAPP')
          pre_orders_sms = PreOrderOtp.where(shop_id: shop.id, is_charged: nil, status: true, ver_type: 'SMS')
          pre_orders_whatsapp = PreOrderOtp.where(shop_id: shop.id, is_charged: nil, status: true, ver_type: 'WHATSAPP')
          prepaid_orders = shop.order_confirmations.where(status: 'COD-Prepaid', is_prepaid_charged: nil)

          # OOM fix: replaced { ActiveRecord-object => price } hashes with
          # { price => [id, id, ...] }. We were keeping every TwilioLog /
          # AbandonedCart / PreOrderOtp row alive in memory just to call
          # update_column on it later — now we only hold integer ids and
          # write per-price groups via update_all. Streams in batches of
          # 500 via find_each so we never load the whole relation at once.
          sms_charge_groups = Hash.new { |h, k| h[k] = [] }
          whatsapp_charge_groups = Hash.new { |h, k| h[k] = [] }
          whatsapp_bsp_charge_groups = Hash.new { |h, k| h[k] = [] }
          abandoned_charge_groups = Hash.new { |h, k| h[k] = [] }
          abandoned_whatsapp_charge_groups = Hash.new { |h, k| h[k] = [] }
          pre_order_charge_groups_sms = Hash.new { |h, k| h[k] = [] }
          pre_order_charge_groups_whatsapp = Hash.new { |h, k| h[k] = [] }

          # Memory: in_batches + pluck loads only the 2-3 columns we actually
          # read instead of instantiating full ActiveRecord objects with ~20
          # columns each. ~30-50x less memory per row at the same correctness.
          sms_charge = 0
          sms_orders.in_batches(of: 500) do |batch|
            batch.pluck(:id, :country_code, :num_segment).each do |id, country_code, num_segment|
              price = pricer.sms(shop, country_code, num_segment)
              next unless price
              sms_charge_groups[price] << id
              sms_charge += price
            end
          end

          whatsapp_charge = 0
          whatsapp_orders.in_batches(of: 500) do |batch|
            batch.pluck(:id, :country_code, :ver_type).each do |id, country_code, ver_type|
              # India V3 shops keep their own category mapping; everyone else uses MessagePricing's.
              price = pricer.whatsapp(shop, country_code,
                                      category: MessagePricing.whatsapp_category_for_ver_type(ver_type),
                                      india_category: PricingV3India.whatsapp_category_for_ver_type(ver_type))
              next unless price
              whatsapp_charge_groups[price] << id
              whatsapp_charge += price
            end
          end

          # BSP WhatsApp — flat MessagePricing::BSP_WHATSAPP_USD commission for every
          # country, plan and category; only a ShopChargeOverride changes it.
          whatsapp_bsp_charge = 0
          whatsapp_bsp_orders.in_batches(of: 500) do |batch|
            batch.pluck(:id, :event_type_key).each do |id, event_type_key|
              price = pricer.bsp_whatsapp(shop, category: PricingV3India.whatsapp_category_for_event(event_type_key))
              next unless price
              whatsapp_bsp_charge_groups[price] << id
              whatsapp_bsp_charge += price
            end
          end

          abandoned_charge = 0
          abandoned_orders.in_batches(of: 500) do |batch|
            batch.pluck(:id, :country_code).each do |id, country_code|
              price = pricer.sms(shop, country_code)
              next unless price
              abandoned_charge_groups[price] << id
              abandoned_charge += price
            end
          end

          abandoned_charge_whatsapp = 0
          abandoned_orders_whatsapp.in_batches(of: 500) do |batch|
            batch.pluck(:id, :country_code).each do |id, country_code|
              price = pricer.whatsapp(shop, country_code, category: :marketing)
              next unless price
              abandoned_whatsapp_charge_groups[price] << id
              abandoned_charge_whatsapp += price
            end
          end

          # Free pre-order OTP campaign: shops that redeemed the ENV-configured
          # coupon (see PreOrderOtpCampaign) send OTPs to India for free. Those
          # rows are collected and settled at $0 below instead of being priced.
          free_india_otp = PreOrderOtpCampaign.free_otp_for_shop?(shop)
          free_pre_order_otp_ids = []

          pre_order_charge_sms = 0
          pre_orders_sms.in_batches(of: 500) do |batch|
            batch.pluck(:id, :country_code).each do |id, country_code|
              if free_india_otp && country_code.to_s.upcase == PreOrderOtpCampaign::FREE_COUNTRY_CODE
                free_pre_order_otp_ids << id
                next
              end
              price = pricer.sms(shop, country_code)
              next unless price
              pre_order_charge_groups_sms[price] << id
              pre_order_charge_sms += price
            end
          end

          pre_order_charge_whatsapp = 0
          pre_orders_whatsapp.in_batches(of: 500) do |batch|
            batch.pluck(:id, :country_code).each do |id, country_code|
              if free_india_otp && country_code.to_s.upcase == PreOrderOtpCampaign::FREE_COUNTRY_CODE
                free_pre_order_otp_ids << id
                next
              end
              price = pricer.whatsapp(shop, country_code, category: :utility)
              next unless price
              pre_order_charge_groups_whatsapp[price] << id
              pre_order_charge_whatsapp += price
            end
          end

          # Settle the free-campaign rows immediately at $0, independent of
          # whether a usage charge goes through — otherwise they'd be swept
          # into the blanket `pre_orders_*.update_all(is_charged: true)` with
          # no explicit price, or rescanned forever on below-threshold shops.
          if free_pre_order_otp_ids.any?
            free_pre_order_otp_ids.each_slice(1000) do |ids|
              PreOrderOtp.where(id: ids).update_all(is_charged: true, actual_charge_applied: 0)
            end
          end

          pre_order_charge = pre_order_charge_sms + pre_order_charge_whatsapp

          ivr_charge = ivr_orders.count * DEFAULT_IVR_CHARGE

          # Calculate prepaid % charge and store per order.
          # Single pass over the relation now: accumulate gross fee for the
          # usage_charge total AND collect net fee (with discount applied)
          # grouped for batched update_all later. Previously we iterated
          # prepaid_orders twice and held every order object in memory.
          prepaid_charge = 0
          prepaid_fee_groups = Hash.new { |h, k| h[k] = [] }
          prepaid_discount_amount = shop.setting.prepaid_discount.to_f
          prepaid_orders.in_batches(of: 500) do |batch|
            batch.pluck(:id, :order_amount).each do |id, order_amount|
              amount = order_amount.to_f
              gross_fee = (amount * 0.02) / 80
              prepaid_charge += gross_fee
              net_fee = ((amount - prepaid_discount_amount) * 0.02) / 80
              prepaid_fee_groups[net_fee] << id
            end
          end

          # Partial payment charge (shop.id > 47500 only)
          partial_payment_charge = 0
          partial_payment_fee_groups = Hash.new { |h, k| h[k] = [] }

          if shop.id > 10000
            rate = PartialTransactionFee.rate_for(shop, plan: shop.plan, setting: shop.setting)
            # Pluck only what we need (4 small columns) instead of loading
            # full OrderConfirmation AR objects. Also kill the N+1: bulk
            # pre-fetch draft fallback order_amounts once instead of
            # find_by'ing per row.
            partial_rows = shop.order_confirmations
                               .where(status: 'COD-Partial-Payment-Received', is_prepaid_charged: nil)
                               .pluck(:id, :currency, :draft_order_id, :order_amount)

            draft_order_ids = partial_rows.map { |row| row[2] }.compact.uniq
            draft_amounts_by_order_id =
              if draft_order_ids.any?
                shop.order_confirmations
                    .where(order_id: draft_order_ids)
                    .pluck(:order_id, :order_amount)
                    .to_h
              else
                {}
              end

            partial_rows.each do |order_id, currency, draft_order_id, order_amount|
              begin
                original_currency = currency || 'INR'

                total_amount =
                  if draft_order_id.present?
                    (draft_amounts_by_order_id[draft_order_id] || order_amount || 0).to_f
                  else
                    (order_amount || 0).to_f
                  end

                usd_value = usd_value_from(total_amount, original_currency) * rate
                partial_payment_fee_groups[usd_value] << order_id
                partial_payment_charge += usd_value

              rescue => e
                Rails.logger.error "Currency conversion failed for order #{order_id}: #{e.message}"
              end
            end
          end

          total_charge = sms_charge + ivr_charge + prepaid_charge + whatsapp_charge +
                         whatsapp_bsp_charge +
                         abandoned_charge + pre_order_charge_sms + pre_order_charge_whatsapp + abandoned_charge_whatsapp +
                         partial_payment_charge

          allocation = nil
          if total_charge > MINIMUM_ORDER_CHARGE
            shop.init_session
            charge_cap = charge_cap_for(shop)
            if total_charge > charge_cap
              allocation = allocate_within_cap(
                charge_cap,
                twilio: [sms_charge_groups, whatsapp_charge_groups, { DEFAULT_IVR_CHARGE => ivr_orders.pluck(:id) }],
                whatsapp_bsp: [whatsapp_bsp_charge_groups],
                abandoned: [abandoned_charge_groups, abandoned_whatsapp_charge_groups],
                pre_order: [pre_order_charge_groups_sms, pre_order_charge_groups_whatsapp],
                order_fees: [prepaid_fee_groups, partial_payment_fee_groups]
              )
              total_charge = allocation[:total]
              capped_out_shops << "#{shop.id} - #{shop.shopify_domain} (cap left $#{charge_cap.round(2)})" if total_charge <= MINIMUM_ORDER_CHARGE
            end
          end

          if total_charge > MINIMUM_ORDER_CHARGE
            total_charge = total_charge.round(2) unless allocation

            usage_charge = ShopifyAPI::UsageCharge.new(
              recurring_application_charge_id: shop.charge_id,
              usage_charge: {
                description: "COD-King-Charges",
                price: total_charge
              }
            )

            begin
              if usage_charge.save && allocation
                Ops::DynamicChargeLedger.record!(charges: 1, amount: usage_charge.price.to_f)
                mark_allocation(shop, allocation[:picked])
                success_usage_charges << "#{shop.id} - #{shop.shopify_domain} -> $#{usage_charge.price} (capped, rest carried over; Remaining: $#{usage_charge.balance_remaining})"
                total_charge_across_shops += usage_charge.price.to_f
                shop.update(risk_level: usage_charge.risk_level)
              elsif usage_charge.persisted?
                Ops::DynamicChargeLedger.record!(
                  charges: 1, amount: usage_charge.price.to_f,
                  sources: {
                    sms: sms_charge, whatsapp: whatsapp_charge, whatsapp_bsp: whatsapp_bsp_charge,
                    preorder: pre_order_charge, abandoned_sms: abandoned_charge,
                    abandoned_whatsapp: abandoned_charge_whatsapp, ivr: ivr_charge,
                    prepaid: prepaid_charge, partial_payment: partial_payment_charge
                  }
                )
                sms_orders.update_all(is_charged: true)
                ivr_orders.update_all(is_charged: true)
                whatsapp_orders.update_all(is_charged: true)
                whatsapp_bsp_orders.update_all(is_charged: true)
                abandoned_orders.update_all(is_charged: true)
                pre_orders_sms.update_all(is_charged: true)
                pre_orders_whatsapp.update_all(is_charged: true)
                abandoned_orders_whatsapp.update_all(is_charged: true)

                # One UPDATE per distinct price instead of one UPDATE per row.
                # Preserves per-order actual_charge_applied values without
                # holding the ActiveRecord objects in memory.
                sms_charge_groups.each { |price, ids| TwilioLog.where(id: ids).update_all(actual_charge_applied: price) }
                whatsapp_charge_groups.each { |price, ids| TwilioLog.where(id: ids).update_all(actual_charge_applied: price) }
                whatsapp_bsp_charge_groups.each { |price, ids| WhatsappMessageLog.where(id: ids).update_all(actual_charge_applied: price) }
                ivr_orders.each { |order| order.update_column(:actual_charge_applied, DEFAULT_IVR_CHARGE) }
                abandoned_charge_groups.each { |price, ids| AbandonedCart.where(id: ids).update_all(actual_charge_applied: price) }
                abandoned_whatsapp_charge_groups.each { |price, ids| AbandonedCart.where(id: ids).update_all(actual_charge_applied: price) }
                pre_order_charge_groups_sms.each { |price, ids| PreOrderOtp.where(id: ids).update_all(actual_charge_applied: price) }
                pre_order_charge_groups_whatsapp.each { |price, ids| PreOrderOtp.where(id: ids).update_all(actual_charge_applied: price) }

                prepaid_fee_groups.each do |fee, ids|
                  shop.order_confirmations.where(id: ids).update_all(cod_fee: fee, is_prepaid_charged: true)
                end

                partial_payment_fee_groups.each do |fee, ids|
                  shop.order_confirmations.where(id: ids).update_all(cod_fee: fee, is_prepaid_charged: true)
                end

                success_usage_charges << "#{shop.id} - #{shop.shopify_domain} -> $#{usage_charge.price} (Remaining: $#{usage_charge.balance_remaining})"
                total_charge_across_shops += usage_charge.price.to_f
                shop.update(risk_level: usage_charge.risk_level)

                total_sms += sms_charge
                total_whatsapp += whatsapp_charge
                total_whatsapp_bsp += whatsapp_bsp_charge
                total_abandoned_sms += abandoned_charge
                total_abandoned_whatsapp += abandoned_charge_whatsapp
                total_preorder += pre_order_charge
                total_ivr += ivr_charge
                total_prepaid += prepaid_charge
                total_partial_payment += partial_payment_charge
              else
                error_usage_charges << "#{shop.id} - #{shop.shopify_domain} -> $#{usage_charge.price}" if shop.id > 25000
              end
            rescue => e
              error_usage_charges << "#{shop.id} - #{shop.shopify_domain} -> $#{usage_charge.price} Error: #{e.message}" if shop.id > 25000
            end
          elsif allocation.nil?
            below_threshold_shops << "#{shop.id} - #{shop.shopify_domain}"
          end
        end
        flush_ledger_counters.call
      end

      flush_ledger_counters.call

      unless @skip_slack_notifications
        SlackNotifier::CLIENT.ping(
          text: "Not activated Charges (#{Rails.env}) \n*Stores Count*: #{not_activated}\n"\
                "*Success Charges*:\n#{success_usage_charges.join("\n")}\n\n"
                # "*Error Charges*:\n#{error_usage_charges.join("\n")}"
        )
        SlackNotifier::CLIENT.ping(
          text: "*Error Charges*:\n#{error_usage_charges.join("\n")}"
        )
        if capped_out_shops.any?
          SlackNotifier::CLIENT.ping(
            text: "*Capped amount used up* (#{Rails.env}) - charges carried over to the next cycle:\n#{capped_out_shops.join("\n")}"
          )
        end

        SlackNotifier::CLIENT.ping(
          text: <<~MSG
            ✅ Total successful charges (#{Rails.env}): $#{total_charge_across_shops.round(2)}

            ✅ Success Count: #{success_usage_charges.count}
            ❌ Error Count: #{error_usage_charges.count}
            ⚠ Below Threshold: #{below_threshold_shops.count}
            🧢 Capped amount used up: #{capped_out_shops.count}

            💰 Category Breakdown:
            • SMS: $#{total_sms.round(2)}
            • WhatsApp (legacy MSG91): $#{total_whatsapp.round(2)}
            • WhatsApp (BSP / own WABA): $#{total_whatsapp_bsp.round(2)}
            • PreOrder OTP: $#{total_preorder.round(2)}
            • Abandoned Cart (SMS): $#{total_abandoned_sms.round(2)}
            • Abandoned Cart (WhatsApp): $#{total_abandoned_whatsapp.round(2)}
            • Prepaid %: $#{total_prepaid.round(2)}
            • Partial Payment Charges: $#{total_partial_payment.round(2)}
          MSG
        )
      end
    rescue => e
      if @skip_slack_notifications
        Rails.logger.error("DynamicChargeJob Rescue Error (#{Rails.env}): #{e.message}\n#{e.backtrace.join("\n")}")
      else
        SlackNotifier::CLIENT.ping(
          text: "DynamicChargeJob Rescue Error: (#{Rails.env}) \n #{e.message}\n#{e.backtrace.join("\n")}"
        )
      end
    ensure
      # Also runs when Sidekiq interrupts the job on shutdown/deploy (Sidekiq::Shutdown is not a StandardError).
      flush_ledger_counters&.call
    end

    private

    # Shopify rejects a usage charge above the subscription's remaining capped
    # balance, so bill only what still fits; unbilled rows stay uncharged for the next cycle.
    def charge_cap_for(shop)
      recurring = ShopifyAPI::RecurringApplicationCharge.find(shop.charge_id)
      remaining = recurring.respond_to?(:balance_remaining) ? recurring.balance_remaining : nil
      return MAX_CHARGE_PER_RUN if recurring.nil? || recurring.capped_amount.blank? || remaining.nil?

      [MAX_CHARGE_PER_RUN, remaining.to_f].min
    rescue StandardError => e
      Rails.logger.warn("[DynamicChargeJob] capped balance lookup failed shop=#{shop.id}: #{e.class}: #{e.message}")
      MAX_CHARGE_PER_RUN
    end

    def allocate_within_cap(cap, buckets)
      left = cap.to_f
      total = 0.0
      picked = Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = [] } }
      buckets.each do |kind, groups|
        groups.each do |group|
          group.each do |price, ids|
            price = price.to_f
            if price <= 0
              picked[kind][price].concat(ids)
              next
            end
            ids.each do |id|
              break if price > left + 1e-9

              picked[kind][price] << id
              left -= price
              total += price
            end
          end
        end
      end
      { total: (total * 100).floor / 100.0, picked: picked }
    end

    def mark_allocation(shop, picked)
      models = { twilio: TwilioLog, whatsapp_bsp: WhatsappMessageLog, abandoned: AbandonedCart, pre_order: PreOrderOtp }
      models.each do |kind, model|
        picked[kind].each do |price, ids|
          ids.each_slice(1000) { |slice| model.where(id: slice).update_all(is_charged: true, actual_charge_applied: price) }
        end
      end
      picked[:order_fees].each do |fee, ids|
        ids.each_slice(1000) { |slice| shop.order_confirmations.where(id: slice).update_all(cod_fee: fee, is_prepaid_charged: true) }
      end
    end

    def usd_value_from(amount, currency)
      money = Money.new((amount * 100).to_i, currency)
      money.exchange_to('USD').to_f
    rescue Money::Bank::UnknownRate
      fallback_rate = ExchangeRateBank.fallback_usd_rate(currency)
      unless fallback_rate
        puts "Missing exchange rate and no fallback for #{currency}"
        return 0
      end

      puts "Using fallback rate for #{currency}: #{fallback_rate}"
      amount * fallback_rate
    end
  end
end