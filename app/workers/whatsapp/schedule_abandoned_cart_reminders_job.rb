module Whatsapp
  # Cron-fired (every 10 min). For each shop with a BSP abandoned_cart
  # binding, walks BOTH abandonment funnels and dispatches any reminder
  # stages that have come due:
  #
  #   1. Shopify checkout abandonment — buyer reached Shopify checkout and
  #      didn't complete. Source: AbandonedCheckoutGraphqlFetcher.
  #   2. Pre-order OTP abandonment — buyer entered phone in the COD King
  #      pre-checkout form and never reached Shopify checkout. Source: the
  #      pre_order_otps table.
  #
  # Both funnels normalize to the same payload shape so the merchant's stage
  # config (template, offset_minutes, discount) applies to either.
  #
  # Dedup is per (shop, source_external_id, stage_index) via
  # WhatsappMessageLog so reruns don't double-send. source_external_id is
  # the Shopify checkout token for funnel 1 and "otp:<id>" for funnel 2 so
  # the two never collide.
  class ScheduleAbandonedCartRemindersJob < ApplicationJob
    sidekiq_options queue: 'administration', retry: false

    # Buffer added on top of the longest configured stage offset when deciding
    # how far back to fetch carts. 24h floor catches the case where a
    # long-offset stage was added recently and we want to send it on older
    # carts still within the stage window.
    FETCH_LOOKBACK_FLOOR = 24.hours

    # Smallest gap between scheduled stages we honour at this cron's granularity.
    MIN_STAGE_RESOLUTION = 1.minute

    # Match the cron cadence in config/schedule.yml. Used to compute a
    # "schedule horizon" — we only schedule stages whose due_at falls within
    # the next tick. Anything further out waits for the next cron run, which
    # keeps duplicate-scheduling impossible without needing pre-write log rows.
    CRON_INTERVAL = 10.minutes

    # If a buyer is actively re-engaging the OTP form, we treat that as an
    # implicit recovery signal and suppress the abandoned reminder. "Active"
    # = an IN_PROGRESS row touched within this window.
    ACTIVE_RE_ENGAGEMENT_WINDOW = 30.minutes

    # Normalized view of an abandoned cart from either source. `anchor_at` is
    # the timestamp every stage's `offset_minutes` is measured from:
    #   - Shopify checkout source → `checkout.created_at` (when the buyer
    #     started checkout and didn't complete; Shopify treats the row as
    #     abandoned from creation).
    #   - Pre-order OTP source → `otp.updated_at` (when the upstream
    #     AdminJobs::PreOrderOtpAbandonmentJob flipped order_status to
    #     'AbandonedCheckout' — i.e. the canonical "we decided this is
    #     abandoned" signal).
    # The dispatch loop just uses anchor_at; it doesn't care which source.
    CartView = Struct.new(
      :kind,                  # :shopify | :otp
      :source_external_id,    # checkout token / "otp:<id>"
      :anchor_at,             # when reminder offsets are measured from
      :payload,               # hash going into DispatchEventJob
      :abandoned_cart,        # AbandonedCart row (for discount cache + recovery flag)
      keyword_init: true
    )

    def perform
      shops_with_binding.find_each do |shop|
        process_shop(shop)
      rescue => e
        Rails.logger.warn("[ac_reminders] shop=#{shop.id} failed: #{e.class}: #{e.message}")
      end
    end

    private

    def shops_with_binding
      shop_ids = WhatsappTemplateBinding
                  .active
                  .where(event_type_key: 'abandoned_cart')
                  .pluck(:shop_id)
                  .uniq
      Shop.where(id: shop_ids)
    end

    def process_shop(shop)
      # Pre-filter on the number abandoned_cart is routed to (falls back to the
      # shop default). Per-stage dispatch re-resolves the account anyway.
      return unless shop.whatsapp_account_for('abandoned_cart')&.ready_to_send?

      stages = shop.whatsapp_template_bindings
                   .active
                   .for_event('abandoned_cart')
                   .ordered_by_stage
                   .to_a
      return if stages.empty?

      resumed_at = stages.filter_map(&:resumed_at).max
      last_paused_at = stages.filter_map(&:last_paused_at).max

      max_offset = stages.map(&:offset_minutes).max.to_i.minutes
      lookback = [max_offset + 6.hours, FETCH_LOOKBACK_FLOOR].max

      carts = each_cart(shop, lookback)
      Rails.logger.info("[ac_reminders] shop=#{shop.id} stages=#{stages.size} carts=#{carts.size}")

      carts.each do |cart_view|
        next if abandoned_while_paused?(cart_view.anchor_at, last_paused_at, resumed_at)

        dispatch_stages_for_cart(shop, cart_view, stages)
      rescue => e
        Rails.logger.warn("[ac_reminders] shop=#{shop.id} cart=#{cart_view&.source_external_id} failed: #{e.class}: #{e.message}")
      end
    end

    def abandoned_while_paused?(anchor_at, last_paused_at, resumed_at)
      return false unless anchor_at && last_paused_at && resumed_at && resumed_at > last_paused_at

      anchor_at >= last_paused_at && anchor_at < resumed_at
    end

    def each_cart(shop, lookback)
      # A shop whose carts are pushed to us over a webhook must not also be
      # polled: Shopflo replaces Shopify's checkout, so polling would either
      # return nothing or duplicate every cart that does come back.
      shopify = shop.webhook_cart_ingestion? ? [] : collect_shopify_checkouts(shop, lookback)
      otps    = collect_pre_order_otps(shop, lookback)
      webhook = collect_webhook_carts(shop, lookback)
      shopify + otps + webhook
    end

    # Carts ingested by Webhooks::ProcessInboundEventJob. The anchor row already
    # holds the normalized payload, so nothing needs re-fetching.
    def collect_webhook_carts(shop, lookback)
      shop.abandoned_carts
          .from_webhooks
          .anchors
          .not_recovered
          .where('abandoned_carts.created_at >= ?', lookback.ago)
          .order(created_at: :desc)
          .filter_map do |ac|
            payload = ac.source_payload
            next if payload.blank? || payload['checkout'].blank?

            CartView.new(
              kind: :webhook,
              source_external_id: ac.checkout_id.to_s,
              anchor_at: parse_time(ac.shopify_created_at) || ac.created_at,
              payload: payload,
              abandoned_cart: ac
            )
          end
    end

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

    def dispatch_stages_for_cart(shop, cart_view, stages)
      # Suppress abandoned-cart reminders when this number already placed an
      # order within the merchant's configured window. `omit_whatsapp_message_ttl`
      # is in minutes; 0 (default) disables the check so other merchants are
      # unaffected.
      ttl = shop.setting&.omit_whatsapp_message_ttl.to_i
      if ttl > 0 && recent_order_for_phone?(shop, cart_view.abandoned_cart&.phone, ttl)
        Rails.logger.info(
          "[ac_reminders] skip shop=#{shop.id} cart=#{cart_view.source_external_id} " \
          "reason=recent_order_within_#{ttl}m"
        )
        return
      end

      anchor_at = cart_view.anchor_at || Time.current
      now = Time.current
      horizon = now + CRON_INTERVAL

      # When the cron catches a cart well after multiple stages came due
      # (e.g. anchor was 10 min ago but stages are at 1 and 5 min), the naive
      # approach would fire every past-due stage with perform_async — and the
      # customer gets two messages in the same second. Track the previous
      # stage's actual fire time + offset so we can enforce the inter-stage
      # gap (5min − 1min = 4min) on the subsequent stage when needed.
      prev_actual_fire = nil
      prev_offset = nil

      stages.each do |binding|
        offset = binding.offset_minutes.to_i.minutes
        natural_due_at = anchor_at + [offset, MIN_STAGE_RESOLUTION].max

        # If a prior stage in this run got rebased to NOW (past-due bumped
        # forward), this stage must wait at least the GAP between its offset
        # and the prior stage's offset — otherwise the customer gets two
        # messages back-to-back. The gap mirrors what the merchant configured.
        if prev_actual_fire && prev_offset
          gap = offset - prev_offset
          earliest_for_gap = prev_actual_fire + gap
          due_at = [natural_due_at, earliest_for_gap].max
        else
          due_at = natural_due_at
        end

        # Stages further out than the next cron tick wait for a later tick —
        # this keeps perform_in scheduling safe from duplicates without
        # needing pre-written log rows. The race window between "we schedule
        # this stage" and "Sidekiq fires it" is bounded by CRON_INTERVAL.
        next if due_at > horizon

        already = WhatsappMessageLog.already_sent_for_stage(
          shop_id: shop.id,
          event_type_key: 'abandoned_cart',
          source_external_id: cart_view.source_external_id,
          stage_index: binding.stage_index
        ).exists?
        next if already

        # If due_at is in the past, fire NOW; otherwise schedule for the
        # exact due_at. actual_fire is what we record for the next iteration
        # so the gap calculation above uses the real fire time, not the
        # historical natural_due_at.
        actual_fire = due_at < now ? now : due_at
        delay_seconds = (actual_fire - now).to_i

        if delay_seconds <= 0
          ::Whatsapp::DispatchEventJob.perform_async(
            'abandoned_cart',
            shop.shopify_domain,
            cart_view.payload,
            false,                                # inline
            nil,                                  # recipient_override
            binding.stage_index
          )
        else
          ::Whatsapp::DispatchEventJob.perform_in(
            delay_seconds.seconds,
            'abandoned_cart',
            shop.shopify_domain,
            cart_view.payload,
            false,
            nil,
            binding.stage_index
          )
        end

        Rails.logger.info(
          "[ac_reminders] schedule shop=#{shop.id} cart=#{cart_view.source_external_id} " \
          "kind=#{cart_view.kind} stage=#{binding.stage_index} " \
          "natural_due=#{natural_due_at} actual_fire=#{actual_fire} delay=#{delay_seconds}s"
        )

        prev_actual_fire = actual_fire
        prev_offset = offset
      end
    end

    # ───────────────────────────────────────────────────────────────────
    # Source 1: Shopify checkout abandonment
    # ───────────────────────────────────────────────────────────────────

    def collect_shopify_checkouts(shop, lookback)
      checkouts = ::ShopifyServices::AbandonedCheckoutGraphqlFetcher
                    .fetch_created_since(shop, lookback.ago)

      Array(checkouts).filter_map do |checkout|
        next unless checkout&.id

        recovery_url = recovery_url_for(checkout)

        # Upsert a row so DiscountResolver has somewhere to cache an
        # auto-generated discount AND the existing OrderConfirmationCreateJob
        # recovery path (which matches on AbandonedCart.checkout_id) can flip
        # `notes` to 'Recovered' later. find_or_create_by → idempotent across
        # cron runs.
        ac = shop.abandoned_carts.find_or_create_by!(checkout_id: checkout.id.to_s) do |row|
          row.url             = recovery_url
          row.phone           = checkout.phone.to_s
          row.country_code    = checkout.shipping_address&.country_code.to_s
          row.notif_type      = 'WHATSAPP'
          row.total_price     = checkout.total_price.to_f
          row.name            = checkout.customer&.first_name.to_s.presence || 'Customer'
          row.shopify_created_at = checkout.created_at
          row.shop_id         = shop.id
        end

        # Rows created before the Shopflo attribute appeared (or before this
        # support shipped) keep pointing at the native checkout — refresh them.
        ac.update(url: recovery_url) if recovery_url.present? && ac.url != recovery_url

        # Skip if this cart was already recovered (set by
        # OrderConfirmationCreateJob when the corresponding order lands).
        next if ac.notes.to_s == 'Recovered'

        CartView.new(
          kind: :shopify,
          source_external_id: checkout.id.to_s,
          anchor_at: parse_time(checkout.created_at),
          payload: shopify_checkout_to_payload(checkout, recovery_url),
          abandoned_cart: ac
        )
      rescue => e
        Rails.logger.warn("[ac_reminders] shop=#{shop.id} shopify cart=#{checkout&.id} skipped: #{e.class}: #{e.message}")
        nil
      end
    end

    # Shopflo-powered stores bypass Shopify's native checkout, so the
    # abandonedCheckoutUrl Shopify reports would drop the buyer on a checkout
    # the store doesn't use. Shopflo stamps the real resumable-checkout link
    # on the abandoned checkout as the `shopflo_checkout_url` note attribute —
    # prefer it whenever present.
    def recovery_url_for(checkout)
      shopflo = Array(checkout.note_attributes)
                  .find { |attr| attr.name.to_s == 'shopflo_checkout_url' }
                  &.value.to_s.strip
      shopflo.presence || checkout.abandoned_checkout_url.to_s
    end

    def shopify_checkout_to_payload(checkout, recovery_url)
      customer = checkout.customer
      shipping = checkout.shipping_address
      billing  = checkout.billing_address

      # OrderProductImageResolver walks `checkout.line_items[]` for an image
      # URL (cheap path) and falls back to ShopifyAPI::Product.find(product_id).
      # The fetcher's LineItemWrapper carries variant_id + product_id but no
      # image — the resolver's API fallback covers that.
      line_items_payload = Array(checkout.line_items).map do |li|
        {
          'title'      => li.respond_to?(:title) ? li.title.to_s : nil,
          'quantity'   => (li.respond_to?(:quantity) ? li.quantity.to_i : 0),
          'variant_id' => li.respond_to?(:variant_id) ? li.variant_id : nil,
          'product_id' => li.respond_to?(:product_id) ? li.product_id : nil
        }.compact
      end

      {
        'checkout' => {
          'id'                       => checkout.id.to_s,
          'token'                    => checkout.id.to_s,
          'abandoned_checkout_url'   => recovery_url.to_s,
          'created_at'               => checkout.created_at.to_s,
          'total_price'              => checkout.total_price.to_s,
          'line_items'               => line_items_payload,
          'line_items_count'         => Array(checkout.line_items).size.to_s,
          'phone'                    => checkout.phone.to_s,
          'customer'                 => {
            'first_name' => customer&.first_name.to_s,
            'phone'      => customer&.phone.to_s
          },
          'shipping_address' => {
            'phone'        => shipping&.phone.to_s,
            'country_code' => shipping&.country_code.to_s
          },
          'billing_address' => {
            'phone'        => billing&.phone.to_s,
            'country_code' => billing&.country_code.to_s
          }
        }
      }
    end

    # ───────────────────────────────────────────────────────────────────
    # Source 2: Pre-order OTP abandonment
    # ───────────────────────────────────────────────────────────────────

    # Only act on rows the upstream cron has decided are abandoned:
    #   - AdminJobs::PreOrderOtpAbandonmentJob (runs every 15min) flips
    #     `order_status` to 'AbandonedCheckout' once it sees the row idle
    #     >30 min. That's our trusted "abandoned" signal — we don't add a
    #     second idle wait.
    #   - IN_PROGRESS rows are NOT picked up here; they're the upstream
    #     cron's responsibility.
    #
    # Lookback applies to `updated_at` (= when we marked it abandoned),
    # because that's also our reminder anchor. A row marked abandoned 23h
    # ago is still in scope for a stage with a long offset; a row marked
    # abandoned 25h ago isn't worth chasing.
    def collect_pre_order_otps(shop, lookback)
      candidates = shop.pre_order_otps
                       .where(order_status: 'AbandonedCheckout')
                       .where('updated_at >= ?', lookback.ago)
                       .where.not(phone: [nil, ''])
                       .to_a

      # Dedup per phone — a buyer who tested the OTP form 3 times has 3
      # AbandonedCheckout rows. Without this, we'd dispatch every reminder
      # stage 3 times to the same phone. Keep only the most recently
      # abandoned cart per phone; the older ones are irrelevant.
      latest_per_phone = candidates.group_by(&:phone).values.map { |group|
        group.max_by(&:updated_at)
      }

      # Recovery suppression: if the buyer is currently active in the OTP
      # form again (a newer IN_PROGRESS row exists), they're recovering on
      # their own — buzzing them with "you left items" would be confusing.
      # The 30-min window matches AdminJobs::PreOrderOtpAbandonmentJob's
      # idle threshold, so once they go quiet for 30 min the upstream cron
      # will flip them to AbandonedCheckout and we'll reconsider.
      active_phones = shop.pre_order_otps
                          .where(order_status: 'IN_PROGRESS')
                          .where('updated_at > ?', ACTIVE_RE_ENGAGEMENT_WINDOW.ago)
                          .where.not(phone: [nil, ''])
                          .pluck(:phone)
                          .to_set
      latest_per_phone.reject! { |o| active_phones.include?(o.phone) }

      latest_per_phone.filter_map do |otp|
        # Skip OTPs whose cart_details aren't usable for a recovery link.
        cart_details = Array(otp.cart_details)
        next if cart_details.empty?

        permalink = build_cart_permalink(shop, otp, cart_details)
        if permalink.blank?
          Rails.logger.warn(
            "[ac_reminders] shop=#{shop.id} otp=#{otp.id} skipped — no usable variant_id/quantity in cart_details. " \
            "First item keys=#{cart_details.first&.keys.inspect}"
          )
          next
        end

        # Must use underscore to match `payload.checkout.token` (which
        # DispatchEventJob derives source_external_id from when writing the
        # log row). Colon vs underscore mismatch silently broke dedup —
        # every cron tick re-fired both stages because the dedup check for
        # "otp:<id>" never matched the stored "otp_<id>" log rows.
        external_id = "otp_#{otp.id}"

        ac = shop.abandoned_carts.find_or_create_by!(checkout_id: external_id) do |row|
          row.url             = permalink
          row.phone           = otp.phone.to_s
          row.country_code    = otp.country_code.to_s
          row.notif_type      = 'WHATSAPP'
          row.total_price     = cart_total(cart_details)
          row.name            = customer_name_for(otp)
          row.shopify_created_at = otp.created_at
          row.shop_id         = shop.id
        end

        # Recovery flag from the regular path. (We also already filtered out
        # ORDER_PLACED at the WHERE level via `order_status: 'AbandonedCheckout'`.)
        next if ac.notes.to_s == 'Recovered'

        CartView.new(
          kind: :otp,
          source_external_id: external_id,
          anchor_at: otp.updated_at,
          payload: pre_order_otp_to_payload(otp, permalink, cart_details),
          abandoned_cart: ac
        )
      rescue => e
        Rails.logger.warn("[ac_reminders] shop=#{shop.id} otp=#{otp&.id} skipped: #{e.class}: #{e.message}")
        nil
      end
    end

    # Tolerate both serialization shapes of `cart_details`:
    #   - snake_case (MSG91-era): variant_id, quantity, price, featured_image
    #   - camelCase  (Storefront/Cart API): variantId, totalQuantity, cost, imageUrl
    # Different OTP entry points wrote different shapes over time, so reading
    # either keeps us resilient instead of silently skipping camelCase rows.
    def item_variant_id(item) ; item['variant_id'] || item['variantId'] ; end
    def item_quantity(item)   ; item['quantity']   || item['totalQuantity'] ; end
    def item_price(item)      ; item['price']      || item['cost'] ; end
    def item_image(item)      ; item['featured_image'] || item['imageUrl'] ; end

    # Build the Shopify cart permalink the same way the merchant-facing
    # CodKingAbandonedCarts.jsx page does (see
    # app/javascript/packs/Components/CodKingAbandonedCarts.jsx#buildShopifyPermalink):
    #
    #   - variant_id is the only hard requirement
    #   - quantity defaults to 1 if missing or non-positive
    #
    # This matches what the merchant sees as their "Copy link" output, so
    # we never send a reminder linking to a different cart than the one the
    # merchant previewed. The `_codkSessionId` is the BSP-specific session
    # tracker the storefront uses to resurrect the cart.
    def build_cart_permalink(shop, otp, cart_details)
      line_items_string = cart_details.filter_map do |item|
        next if item.blank?
        variant_id = item_variant_id(item)
        next if variant_id.blank?

        # Partial-payment SKUs resolve back to their underlying variant.
        mapping = PartialProductMapping.find_by(partial_variant_id: variant_id) if defined?(PartialProductMapping)
        if mapping&.original_variant_ids&.first.present?
          variant_id = mapping.original_variant_ids.first.split(':').first
        end

        qty = item_quantity(item).to_i
        qty = 1 if qty <= 0

        "#{variant_id}:#{qty}"
      end
      return nil if line_items_string.empty?

      "https://#{shop.shopify_domain}/cart/#{line_items_string.join(',')}?storefront=true&_codkSessionId=#{otp.device_id}"
    end

    def cart_total(cart_details)
      cart_details.sum { |i| item_price(i).to_f * item_quantity(i).to_i }
    end

    # Same lookup the MSG91 path uses: phone → Customer table for a friendly
    # first name. Falls back to "Customer" so templates never render as blank.
    def customer_name_for(otp)
      customer = Customer.find_by(phone: otp.phone)
      return 'Customer' unless customer

      first = customer.first_name.to_s.strip
      last  = customer.last_name.to_s.strip
      first.presence || last.presence || 'Customer'
    end

    # Build a payload shaped like the Shopify checkout one so the same
    # `abandoned_cart` event variables (customer.first, cart.total,
    # cart.recovery_url, cart.items_count) resolve without special-casing.
    #
    # `line_items` is included with one entry per cart_details item, carrying
    # the actual product image at `line_items[].image.src` — that's where
    # OrderProductImageResolver looks first when the template's header_media
    # mode is 'order_product_image'. Without this, the resolver returns nil
    # and the dispatch falls back to the template's static example_url (the
    # sample image picked at template-creation time).
    def pre_order_otp_to_payload(otp, permalink, cart_details)
      total = cart_total(cart_details)
      items_count = cart_details.sum { |i|
        # Mirror the permalink builder: default to 1 if quantity is missing/zero.
        q = item_quantity(i).to_i
        q > 0 ? q : 1
      }
      featured_image = cart_details.find { |i| item_image(i).present? }.then { |i| item_image(i) if i }

      line_items_payload = cart_details.map do |i|
        next nil if i.blank?
        qty = item_quantity(i).to_i
        qty = 1 if qty <= 0
        img = item_image(i)
        {
          'title'      => i['title'].to_s,
          'quantity'   => qty,
          'price'      => item_price(i).to_f,
          'variant_id' => item_variant_id(i),
          'product_id' => (i['product_id'] || i['productId']),
          # Both shapes the resolver checks first — image.src and the legacy
          # image_url top-level — so it never has to hit the Shopify API for
          # OTP carts.
          'image'      => (img.present? ? { 'src' => img.to_s } : nil),
          'image_url'  => img&.to_s
        }.compact
      end.compact

      {
        'checkout' => {
          'id'                       => "otp_#{otp.id}",
          'token'                    => "otp_#{otp.id}",
          'abandoned_checkout_url'   => permalink,
          'created_at'               => otp.created_at.to_s,
          'total_price'              => total.to_s,
          'line_items'               => line_items_payload,
          'line_items_count'         => items_count.to_s,
          'phone'                    => otp.phone.to_s,
          'featured_image'           => featured_image,
          'customer'                 => {
            'first_name' => customer_name_for(otp),
            'phone'      => otp.phone.to_s
          },
          'shipping_address' => {
            'phone'        => otp.phone.to_s,
            'country_code' => otp.country_code.to_s
          },
          'billing_address' => {
            'phone'        => otp.phone.to_s,
            'country_code' => otp.country_code.to_s
          }
        }
      }
    end

    def parse_time(value)
      return value if value.is_a?(Time)
      return Time.parse(value.to_s) if value.respond_to?(:to_s)
    rescue ArgumentError
      nil
    end
  end
end
