module Whatsapp
  # Code-defined registry of every "thing that can trigger a WhatsApp message".
  # Each event declares:
  #   - kind: :transactional (Shopify webhook driven) or :campaign (manual broadcast)
  #   - template_category: the WhatsApp template category that's compatible with this event
  #   - variables: the allow-list of variables a template bound to this event can use
  #
  # Adding a new event = add one entry below + (optionally) wire its dispatch source.
  # Adding a new variable to an existing event = add to that event's :variables array.
  class EventRegistry
    ORDER_VARIABLES = [
      { key: 'customer.first',   label: 'Customer first name', sample: 'Aman',     path: 'order.customer.first_name' },
      { key: 'order.id',         label: 'Order number',        sample: '#1023',    path: 'order.name' },
      { key: 'order.total',      label: 'Order total',         sample: '₹2,499',   path: 'order.total_price' },
      { key: 'order.items_count',label: 'Number of items',     sample: '3',        path: 'order.line_items_count' },
      { key: 'order.products',   label: 'Product details',     sample: 'Product 1 : Qty 1, Product 2 : Qty 2', path: 'order.line_items', format: :line_items_summary },
      { key: 'order.shipping_address', label: 'Shipping address', sample: '12 MG Rd, Mumbai 400001, IN', path: 'order.shipping_address', format: :postal_address },
      { key: 'order.status_url', label: 'Order status URL',    sample: 'https://shop.com/orders/abc', path: 'order.order_status_url', kind: :url },
      { key: 'store.name',       label: 'Store name',          sample: 'MyShop',   path: 'shop.name' },
      { key: 'store.url',        label: 'Store URL',           sample: 'https://myshop.com', path: 'shop.url', kind: :url }
    ].freeze

    TRACKING_VARIABLES = [
      { key: 'tracking.number',  label: 'Tracking number',     sample: 'BD9183471',    path: 'fulfillment.tracking_number' },
      { key: 'tracking.url',     label: 'Tracking URL',        sample: 'https://track.example.com/BD9183471', path: 'fulfillment.tracking_url', kind: :url },
      { key: 'tracking.carrier', label: 'Carrier',             sample: 'BlueDart',     path: 'fulfillment.tracking_company' },
      { key: 'delivery.estimated', label: 'Estimated delivery', sample: '18 Oct',     path: 'delivery.estimated_label' }
    ].freeze

    EVENT_TYPES = [
      {
        key: 'order_created',
        label: 'Order placed',
        description: 'Fires every time a new order is placed.',
        kind: :transactional,
        template_category: 'UTILITY',
        source: 'shopify_webhook:orders/create',
        variables: [
          { key: 'customer.first',   label: 'Customer first name', sample: 'Aman',     path: 'order.customer.first_name' },
          { key: 'customer.last',    label: 'Customer last name',  sample: 'Singh',    path: 'order.customer.last_name' },
          { key: 'order.id',         label: 'Order number',        sample: '#1023',    path: 'order.name' },
          { key: 'order.total',      label: 'Order total',         sample: '₹2,499',   path: 'order.total_price' },
          { key: 'order.currency',   label: 'Currency',            sample: 'INR',      path: 'order.currency' },
          { key: 'order.items_count',label: 'Number of items',     sample: '3',        path: 'order.line_items_count' },
          { key: 'order.products',   label: 'Product details',     sample: 'Product 1 : Qty 1, Product 2 : Qty 2', path: 'order.line_items', format: :line_items_summary },
          { key: 'order.status_url', label: 'Order status URL',    sample: 'https://shop.com/orders/abc', path: 'order.order_status_url', kind: :url },
          { key: 'order.shipping_address', label: 'Shipping address', sample: '12 MG Rd, Mumbai 400001, IN', path: 'order.shipping_address', format: :postal_address },
          { key: 'store.name',       label: 'Store name',          sample: 'MyShop',   path: 'shop.name' },
          # Partial-payment amounts (blank for non-partial orders). Computed and
          # injected at dispatch time — see DispatchEventJob#inject_partial_into_payload.
          { key: 'partial.paid',      label: 'Amount paid online',   sample: '₹500',   path: 'partial.paid' },
          { key: 'partial.remaining', label: 'Balance on delivery',  sample: '₹1,999', path: 'partial.remaining' },
          { key: 'partial.total',     label: 'Order total (partial)', sample: '₹2,499', path: 'partial.total' },
        ]
      },
      {
        # Sibling of `order_created`, used ONLY for orders placed as a partial
        # payment (advance paid online, balance on delivery). When a shop binds
        # a template to this event, DispatchEventJob routes partial-payment
        # orders here instead of the normal order_created template — so a shop
        # can run two distinct confirmation messages: this one for
        # partial-paid orders, order_created for everything else. Shops that
        # don't bind this event keep today's behaviour (a single order_created
        # template with partial.* variables populated only for partial orders).
        key: 'order_created_partial',
        label: 'Order placed — partial payment',
        description: 'Fires when a new order is placed as a partial payment (advance paid online, balance on delivery). Falls back to the normal "Order placed" template when not bound.',
        kind: :transactional,
        template_category: 'UTILITY',
        source: 'shopify_webhook:orders/create',
        variables: [
          { key: 'customer.first',   label: 'Customer first name', sample: 'Aman',     path: 'order.customer.first_name' },
          { key: 'customer.last',    label: 'Customer last name',  sample: 'Singh',    path: 'order.customer.last_name' },
          { key: 'order.id',         label: 'Order number',        sample: '#1023',    path: 'order.name' },
          { key: 'order.total',      label: 'Order total',         sample: '₹2,499',   path: 'order.total_price' },
          { key: 'order.currency',   label: 'Currency',            sample: 'INR',      path: 'order.currency' },
          { key: 'order.items_count',label: 'Number of items',     sample: '3',        path: 'order.line_items_count' },
          { key: 'order.products',   label: 'Product details',     sample: 'Product 1 : Qty 1, Product 2 : Qty 2', path: 'order.line_items', format: :line_items_summary },
          { key: 'order.status_url', label: 'Order status URL',    sample: 'https://shop.com/orders/abc', path: 'order.order_status_url', kind: :url },
          { key: 'order.shipping_address', label: 'Shipping address', sample: '12 MG Rd, Mumbai 400001, IN', path: 'order.shipping_address', format: :postal_address },
          { key: 'store.name',       label: 'Store name',          sample: 'MyShop',   path: 'shop.name' },
          # Always populated for this event (every order routed here is a
          # partial-payment order) — see DispatchEventJob#inject_partial_into_payload.
          { key: 'partial.paid',      label: 'Amount paid online',   sample: '₹500',   path: 'partial.paid' },
          { key: 'partial.remaining', label: 'Balance on delivery',  sample: '₹1,999', path: 'partial.remaining' },
          { key: 'partial.total',     label: 'Order total (partial)', sample: '₹2,499', path: 'partial.total' },
        ]
      },
      {
        key: 'order_fulfilled',
        label: 'Order fulfilled',
        description: 'Fires when an order is fulfilled and has tracking info.',
        kind: :transactional,
        template_category: 'UTILITY',
        source: 'shopify_webhook:fulfillments/create',
        variables: [
          { key: 'customer.first',    label: 'Customer first name', sample: 'Aman',         path: 'order.customer.first_name' },
          { key: 'order.id',          label: 'Order number',        sample: '#1023',        path: 'order.name' },
          { key: 'order.total',       label: 'Order total',         sample: '₹2,499',       path: 'order.total_price' },
          { key: 'order.currency',    label: 'Currency',            sample: 'INR',          path: 'order.currency' },
          { key: 'tracking.number',   label: 'Tracking number',     sample: 'BD9183471',    path: 'fulfillment.tracking_number' },
          { key: 'tracking.url',      label: 'Tracking URL',        sample: 'https://track.example.com/BD9183471', path: 'fulfillment.tracking_url', kind: :url },
          { key: 'tracking.carrier',  label: 'Carrier',             sample: 'BlueDart',     path: 'fulfillment.tracking_company' },
          { key: 'order.products',    label: 'Product details',     sample: 'Product 1 : Qty 1, Product 2 : Qty 2', path: 'order.line_items', format: :line_items_summary },
          { key: 'order.status_url',  label: 'Order status URL',    sample: 'https://shop.com/orders/abc', path: 'order.order_status_url', kind: :url },
          { key: 'order.shipping_address', label: 'Shipping address', sample: '12 MG Rd, Mumbai 400001, IN', path: 'order.shipping_address', format: :postal_address },
          { key: 'store.name',        label: 'Store name',          sample: 'MyShop',       path: 'shop.name' },
        ]
      },
      {
        key: 'first_time_purchase',
        label: 'First-time purchase',
        description: "Fires once per customer, on their first ever order with the shop.",
        kind: :transactional,
        # First-purchase messages can fit either category — a plain thank-you
        # is UTILITY, a welcome offer with a coupon is MARKETING. Submit as
        # whichever the wording fits; Meta auto-upgrades to MARKETING during
        # review if the body skews promotional.
        template_category: 'UTILITY',
        bindable_categories: %w[UTILITY MARKETING],
        source: 'shopify_webhook:orders/create',
        variables: [
          { key: 'customer.first',   label: 'Customer first name', sample: 'Aman',      path: 'order.customer.first_name' },
          { key: 'order.id',         label: 'Order number',        sample: '#1023',     path: 'order.name' },
          { key: 'order.total',      label: 'Order total',         sample: '₹2,499',    path: 'order.total_price' },
          { key: 'order.products',   label: 'Product details',     sample: 'Product 1 : Qty 1, Product 2 : Qty 2', path: 'order.line_items', format: :line_items_summary },
          { key: 'order.shipping_address', label: 'Shipping address', sample: '12 MG Rd, Mumbai 400001, IN', path: 'order.shipping_address', format: :postal_address },
          { key: 'store.name',       label: 'Store name',          sample: 'MyShop',    path: 'shop.name' },
        ]
      },
      {
        key: 'abandoned_cart',
        label: 'Abandoned cart',
        description: 'Fires when a customer enters checkout but does not complete the order.',
        kind: :transactional,
        # Recovery messages can be UTILITY (simple "you left items") or
        # MARKETING (incentive / discount). Submit as whichever the wording
        # fits — Meta auto-upgrades to MARKETING on review if the body skews
        # promotional. UTILITY is the default because pricing is lower in
        # most markets.
        template_category: 'UTILITY',
        bindable_categories: %w[UTILITY MARKETING],
        source: 'shopify_webhook:checkouts/update',
        variables: [
          { key: 'customer.first',   label: 'Customer first name', sample: 'Aman',                  path: 'checkout.customer.first_name' },
          { key: 'cart.recovery_url',label: 'Recovery URL',        sample: 'https://shop.com/r/X',  path: 'checkout.abandoned_checkout_url', kind: :url },
          { key: 'cart.total',       label: 'Cart total',          sample: '₹2,499',                path: 'checkout.total_price' },
          { key: 'cart.items_count', label: 'Items in cart',       sample: '2',                     path: 'checkout.line_items_count' },
          { key: 'cart.products',    label: 'Product details',     sample: 'Product 1 : Qty 1, Product 2 : Qty 2', path: 'checkout.line_items', format: :line_items_summary },
          # Discount variables — only populated when the merchant configures a
          # discount on the binding's stage (none / static / auto-generated
          # Shopify price rule). DispatchEventJob runs DiscountResolver and
          # injects the resolved values into the payload at `discount.*` before
          # variable resolution, so these paths read straight out of the payload.
          { key: 'discount.code',      label: 'Discount code',    sample: 'COMEBACK10', path: 'discount.code' },
          # `value` arrives pre-formatted from DiscountResolver: "10%" for
          # percent discounts, "₹500" (shop currency) for fixed amounts.
          { key: 'discount.value',     label: 'Discount value',   sample: '10%',        path: 'discount.value' },
          { key: 'discount.formatted', label: 'Discount (formatted)', sample: '10% off', path: 'discount.formatted' },
          { key: 'store.name',       label: 'Store name',          sample: 'MyShop',                path: 'shop.name' },
        ]
      },
      {
        key: 'cart_abandoned',
        label: 'Cart abandoned',
        description: 'Fires when a customer adds items to the cart but never reaches checkout. Requires an inbound webhook source.',
        kind: :transactional,
        template_category: 'MARKETING',
        bindable_categories: %w[UTILITY MARKETING],
        source: 'webhook:added_to_cart_ui',
        variables: [
          { key: 'customer.first',    label: 'Customer first name', sample: 'Aman',                 path: 'cart.customer.first_name' },
          { key: 'cart.url',          label: 'Cart URL',            sample: 'https://shop.com/cart/1:1', path: 'cart.cart_url', kind: :url },
          { key: 'cart.total',        label: 'Cart total',          sample: '2,499',                path: 'cart.total_price' },
          { key: 'cart.items_count',  label: 'Items in cart',       sample: '2',                    path: 'cart.line_items_count' },
          { key: 'cart.products',     label: 'Product details',     sample: 'Product 1 : Qty 1, Product 2 : Qty 2', path: 'cart.line_items', format: :line_items_summary },
          { key: 'discount.code',      label: 'Discount code',        sample: 'COMEBACK10', path: 'discount.code' },
          { key: 'discount.value',     label: 'Discount value',       sample: '10%',        path: 'discount.value' },
          { key: 'discount.formatted', label: 'Discount (formatted)', sample: '10% off',    path: 'discount.formatted' },
          { key: 'store.name',        label: 'Store name',          sample: 'MyShop',               path: 'shop.name' },
        ]
      },
      {
        key: 'browse_abandoned',
        label: 'Browse abandoned',
        description: 'Fires when a customer views a product and leaves without adding it to the cart. Requires an inbound webhook source.',
        kind: :transactional,
        template_category: 'MARKETING',
        bindable_categories: %w[MARKETING],
        source: 'webhook:product_page_viewed',
        variables: [
          { key: 'customer.first',  label: 'Customer first name', sample: 'Aman',                            path: 'browse.customer.first_name' },
          { key: 'product.name',    label: 'Product name',        sample: 'Cotton Pencil Pants',             path: 'browse.product_name' },
          { key: 'product.price',   label: 'Product price',       sample: '799.00',                          path: 'browse.product_price' },
          { key: 'product.url',     label: 'Product URL',         sample: 'https://shop.com/products/x',     path: 'browse.product_url', kind: :url },
          { key: 'product.image',   label: 'Product image',       sample: 'https://cdn.shopify.com/x.jpg',   path: 'browse.product_image' },
          { key: 'store.name',      label: 'Store name',          sample: 'MyShop',                          path: 'shop.name' },
        ]
      },
      {
        key: 'cod_verification',
        label: 'COD order verification',
        description: 'Fires after a cash-on-delivery order is placed. Customer taps Confirm to proceed or Cancel to cancel the order.',
        kind: :transactional,
        template_category: 'UTILITY',
        bindable_categories: %w[UTILITY],
        # Drives an OrderConfirmationCreateJob branch, not a Shopify webhook
        # subscription of its own.
        source: 'internal:cod_verification',
        # This event requires a template with two QUICK_REPLY buttons whose
        # payloads are exactly these strings. The labels are merchant-editable;
        # the payloads stay fixed because the webhook handler matches on them
        # to decide Confirm vs Cancel.
        required_quick_reply_payloads: %w[cod_confirm cod_cancel],
        variables: [
          { key: 'customer.first',   label: 'Customer first name', sample: 'Aman',     path: 'order.customer.first_name' },
          { key: 'order.id',         label: 'Order number',        sample: '#1023',    path: 'order.name' },
          { key: 'order.total',      label: 'Order total',         sample: '₹2,499',   path: 'order.total_price' },
          { key: 'order.items_count',label: 'Number of items',     sample: '3',        path: 'order.line_items_count' },
          { key: 'order.products',   label: 'Product details',     sample: 'Product 1 : Qty 1, Product 2 : Qty 2', path: 'order.line_items', format: :line_items_summary },
          { key: 'order.shipping_address', label: 'Shipping address', sample: '12 MG Rd, Mumbai 400001, IN', path: 'order.shipping_address', format: :postal_address },
          { key: 'order.status_url', label: 'Order status URL',    sample: 'https://shop.com/orders/abc', path: 'order.order_status_url', kind: :url },
          { key: 'store.name',       label: 'Store name',          sample: 'MyShop',   path: 'shop.name' },
        ]
      },
      {
        key: 'cod_to_prepaid',
        label: 'COD to prepaid',
        description: 'Asks the customer to convert a COD order to prepaid via a payment link, with an optional discount. Use a dynamic URL button with base https://cutt.ly/ — the payment link slug is filled in at send time.',
        kind: :transactional,
        template_category: 'UTILITY',
        # A plain "pay now" nudge is UTILITY; a discount incentive skews
        # MARKETING. Meta auto-upgrades during review if the body is promotional.
        bindable_categories: %w[UTILITY MARKETING],
        # Driven by the prepaid reminders scheduler
        # (NetworkServices::SendPrepaidMessageService), not a Shopify webhook.
        source: 'internal:cod_to_prepaid',
        variables: [
          { key: 'customer.first', label: 'Customer first name',          sample: 'Aman',    path: 'order.customer.first_name' },
          { key: 'customer.name',  label: 'Customer full name',           sample: 'Aman Singh', path: 'order.customer.name' },
          { key: 'store.name',    label: 'Store name',                    sample: 'MyShop',  path: 'shop.name' },
          { key: 'order.id',      label: 'Order number',                  sample: '#1023',   path: 'order.name' },
          { key: 'order.total',   label: 'Order total (COD)',             sample: '₹2,499',  path: 'order.total' },
          { key: 'prepaid.total', label: 'Prepaid total (after discount)', sample: '₹2,199', path: 'prepaid.total' },
          { key: 'payment.link',  label: 'Payment link',                  sample: 'https://cutt.ly/abc123', path: 'payment.link', kind: :url },
        ]
      },
      {
        key: 'campaign_broadcast',
        label: 'Campaign broadcast',
        description: 'Marketing broadcast sent from the Campaigns flow to a chosen audience. Variables map to audience fields per campaign — the recipient variables below are always available.',
        kind: :campaign,
        template_category: 'MARKETING',
        bindable_categories: %w[MARKETING],
        # Not webhook driven — launched manually from the Campaigns page.
        # SendCampaignMessageJob logs sends under this key; DispatchEventJob
        # already knows its recipient path (customer.phone).
        source: 'internal:campaign_broadcast',
        # These mirror Whatsapp::CampaignMessageBuilder#field_lookup, which is
        # what actually resolves campaign variables at send time. Audience
        # specific fields (csv.*, cart.*) are mapped per campaign in the
        # Campaigns flow, so they're not listed here.
        variables: [
          { key: 'recipient.name',  label: 'Recipient name',  sample: 'Aman',                path: 'recipient.name' },
          { key: 'recipient.phone', label: 'Recipient phone', sample: '+919876543210',       path: 'recipient.phone' },
          { key: 'recipient.email', label: 'Recipient email', sample: 'aman@example.com',    path: 'recipient.email' },
        ]
      },
      {
        key: 'pre_order_otp',
        label: 'OTP message',
        description: 'Sends a one-time verification code to the customer before checkout (COD / pre-order verification).',
        kind: :transactional,
        template_category: 'AUTHENTICATION',
        # Not Shopify-webhook driven — triggered internally by the OTP flow
        # (NetworkServices::SendPreOrderOtpService), which supplies the code.
        source: 'internal:pre_order_otp',
        variables: [
          { key: 'otp.code', label: 'OTP code', sample: '1234', source: :literal },
        ]
      },
      {
        key: 'cod_verification_reminder',
        label: 'COD verification reminder',
        description: 'Reminds the customer to confirm a COD order they have not answered yet. Uses the same Confirm / Cancel buttons. Sent 2 hours after the verification message unless you set a delay; skipped once the order is confirmed, cancelled or paid.',
        kind: :transactional,
        template_category: 'UTILITY',
        bindable_categories: %w[UTILITY],
        source: 'internal:cod_verification_reminder',
        follows: 'cod_verification',
        default_offset_minutes: 120,
        relevance: :cod_unverified,
        required_quick_reply_payloads: %w[cod_confirm cod_cancel],
        variables: ORDER_VARIABLES
      },
      {
        key: 'order_cancelled',
        label: 'Order cancelled',
        description: 'Fires when an order is cancelled in Shopify (by the store, auto-cancel or Shopify). Skipped when the customer cancelled it on WhatsApp.',
        kind: :transactional,
        template_category: 'UTILITY',
        bindable_categories: %w[UTILITY],
        source: 'shopify_webhook:orders/cancelled',
        webhook_topic: 'orders/cancelled',
        relevance: :not_customer_cancelled,
        variables: ORDER_VARIABLES + [
          { key: 'order.cancel_reason', label: 'Cancel reason', sample: 'Out of stock', path: 'order.cancel_reason_label' }
        ]
      },
      {
        key: 'order_out_for_delivery',
        label: 'Out for delivery',
        description: 'Fires when the courier marks the shipment out for delivery. Needs your shipping app to update the fulfilment status in Shopify.',
        kind: :transactional,
        template_category: 'UTILITY',
        bindable_categories: %w[UTILITY],
        source: 'shopify_webhook:fulfillment_events/create',
        webhook_topic: 'fulfillment_events/create',
        variables: ORDER_VARIABLES + TRACKING_VARIABLES
      },
      {
        key: 'order_delivered',
        label: 'Order delivered',
        description: 'Fires when the courier marks the shipment delivered. Needs your shipping app to update the fulfilment status in Shopify.',
        kind: :transactional,
        template_category: 'UTILITY',
        bindable_categories: %w[UTILITY],
        source: 'shopify_webhook:fulfillment_events/create',
        webhook_topic: 'fulfillment_events/create',
        variables: ORDER_VARIABLES + TRACKING_VARIABLES
      },
      {
        key: 'feedback_request',
        label: 'Feedback request',
        description: 'Asks for feedback or a review after delivery. Sent 1 day after delivery unless you set a delay.',
        kind: :transactional,
        template_category: 'UTILITY',
        bindable_categories: %w[UTILITY MARKETING],
        source: 'shopify_webhook:fulfillment_events/create',
        webhook_topic: 'fulfillment_events/create',
        follows: 'order_delivered',
        default_offset_minutes: 1440,
        variables: ORDER_VARIABLES
      },
      {
        key: 'reorder_reminder',
        label: 'Reorder reminder',
        description: 'Reminds the customer to buy again after delivery. Sent 30 days after delivery unless you set a delay; skipped if they have ordered again.',
        kind: :transactional,
        template_category: 'MARKETING',
        bindable_categories: %w[MARKETING],
        source: 'shopify_webhook:fulfillment_events/create',
        webhook_topic: 'fulfillment_events/create',
        follows: 'order_delivered',
        default_offset_minutes: 43_200,
        relevance: :not_reordered,
        variables: ORDER_VARIABLES
      },
    ].freeze

    DISPLAY_ORDER = %w[
      order_created order_created_partial cod_verification cod_verification_reminder cod_to_prepaid
      order_fulfilled order_out_for_delivery order_delivered feedback_request reorder_reminder order_cancelled
    ].freeze

    ORDER_EVENT_KEYS = %w[
      order_created order_created_partial order_fulfilled first_time_purchase cod_verification cod_to_prepaid
      cod_verification_reminder order_cancelled order_out_for_delivery order_delivered feedback_request reorder_reminder
    ].freeze

    def self.all
      EVENT_TYPES
    end

    def self.webhook_event?(event)
      event[:source].to_s.start_with?('webhook:')
    end

    def self.default_offset_minutes(key)
      find(key)&.dig(:default_offset_minutes).to_i
    end

    def self.relevance(key)
      find(key)&.dig(:relevance)
    end

    def self.follow_ups_for(key)
      EVENT_TYPES.select { |e| e[:follows] == key.to_s }.map { |e| e[:key] }
    end

    def self.webhook_topic(key)
      find(key)&.dig(:webhook_topic)
    end

    def self.find(key)
      EVENT_TYPES.find { |e| e[:key] == key.to_s }
    end

    def self.variables_for(key)
      event = find(key)
      event ? event[:variables] : []
    end

    def self.url_variables_for(key)
      variables_for(key).select { |v| v[:kind] == :url }
    end

    def self.variable(event_key, var_key)
      variables_for(event_key).find { |v| v[:key] == var_key.to_s }
    end

    def self.compatible_category(key)
      event = find(key)
      event && event[:template_category]
    end

    # Quick-reply button payloads that templates bound to this event must
    # expose (and merchants can't change). Used by both the binding
    # validation and the inbound webhook → action lookup. Returns [] for
    # events with no fixed-payload requirement.
    def self.required_quick_reply_payloads_for(key)
      event = find(key)
      Array(event && event[:required_quick_reply_payloads])
    end

    # Reverse lookup: given a quick-reply payload an inbound webhook handed
    # us, return the event_type_key whose required_quick_reply_payloads
    # contains it. Used to route Confirm/Cancel button taps to the right
    # action without storing the routing on the message log.
    def self.event_for_quick_reply_payload(payload)
      key = payload.to_s
      return nil if key.blank?
      EVENT_TYPES.find { |e|
        Array(e[:required_quick_reply_payloads]).include?(key)
      }&.dig(:key)
    end

    # All template categories that may be bound to this event. Defaults to
    # the single `template_category` for events that don't list extras.
    def self.bindable_categories_for(key)
      event = find(key)
      return [] unless event
      Array(event[:bindable_categories]).presence ||
        Array(event[:template_category]).compact
    end

    # Serialise the registry for the API. Symbols → strings for JSON.
    # Webhook-sourced events are configured in the webhooks section, not the
    # automations page, so the events API never serves them.
    def self.as_json
      EVENT_TYPES.reject { |e| webhook_event?(e) }
                 .sort_by.with_index { |e, i| [DISPLAY_ORDER.index(e[:key]) || DISPLAY_ORDER.size, i] }
                 .map do |e|
        {
          key: e[:key],
          label: e[:label],
          description: e[:description],
          kind: e[:kind].to_s,
          template_category: e[:template_category],
          bindable_categories: bindable_categories_for(e[:key]),
          required_quick_reply_payloads: Array(e[:required_quick_reply_payloads]),
          default_offset_minutes: e[:default_offset_minutes],
          follows: e[:follows],
          variables: e[:variables].map do |v|
            {
              key: v[:key],
              label: v[:label],
              sample: v[:sample],
              source: v[:source]&.to_s,
              kind: v[:kind]&.to_s,
              format: v[:format]&.to_s
            }.compact
          end
        }
      end
    end
  end
end
