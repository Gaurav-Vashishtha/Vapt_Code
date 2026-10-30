module Whatsapp
  # Curated catalog of pre-made templates that merchants can submit to Meta
  # in one click. Each entry maps to an EventRegistry event, supplies vetted
  # copy that's been reviewed against Meta's policy, and pre-fills
  # variable_mapping + url_button so the result is dispatch-ready on approval.
  #
  # Organising principle:
  #   - Most entries have an IMAGE header — engagement on image-headered
  #     transactional templates is materially higher (Meta's own data).
  #   - One or two text-only entries per category for shops that don't want
  #     to maintain a banner asset, or whose Meta account is in a strict
  #     review state where IMAGE templates take longer.
  #   - "Premium" variants surface every variable the event exposes —
  #     shipping address, items count, totals — for merchants who want to
  #     pack maximum context into the message.
  #
  # When adding a new entry:
  #   - Use lowercase_snake_case for `name_suggestion` (Meta's naming rule).
  #   - Body text must be ≤1024 chars; footer ≤60; header text ≤60.
  #   - Every {{N}} in the body must appear in `variable_mapping`, and the
  #     example.body_text array order must match the {{N}} positions.
  #   - For URL buttons with a {{1}}, register them as `https://cutt.ly/{{1}}`
  #     — the TemplateService normalises this at create time.
  class TemplateLibrary
    ENTRIES = [
      # ─────────────────────────────────────────────────────────────────────
      # ORDER PLACED — order_created
      # ─────────────────────────────────────────────────────────────────────
      {
        key: 'order_confirmation_basic',
        title: 'Order confirmation — simple text',
        description: 'Plain confirmation, no image header. Lowest review friction; ships fast. Use this if you don\'t have a branded banner ready.',
        category: 'UTILITY',
        event_type_key: 'order_created',
        tags: %w[transactional simple no-image],
        language: 'en_US',
        name_suggestion: 'order_confirmation_v1',
        components: [
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, thanks for your order! 🎉\n\nYour order *{{2}}* is confirmed and we're packing it now. We'll let you know as soon as it ships.",
            'example' => { 'body_text' => [['Aman', '#1023']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'URL', 'text' => 'View order', 'url' => 'https://cutt.ly/{{1}}', 'example' => ['https://cutt.ly/abc123'] }
            ]
          }
        ],
        variable_mapping: { '1' => 'customer.first', '2' => 'order.id' },
        url_button: { 'mode' => 'predefined', 'variable' => 'order.status_url', 'text' => 'View order' }
      },
      {
        key: 'order_confirmation_with_image',
        title: 'Order confirmation — branded image',
        description: 'Image-headered confirmation. Pair with your shop banner, a thank-you graphic, or "Use the order\'s product image" so each customer sees what they bought.',
        category: 'UTILITY',
        event_type_key: 'order_created',
        tags: %w[transactional popular image],
        language: 'en_US',
        name_suggestion: 'order_confirmation_image_v1',
        components: [
          { 'type' => 'HEADER', 'format' => 'IMAGE' },
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, your order *{{2}}* is in!\n\nWe're getting your *{{3}} item(s)* ready and we'll send you tracking as soon as it ships.\n\nThanks for shopping with {{4}} — see you again soon!",
            'example' => { 'body_text' => [['Aman', '#1023', '3', 'MyShop']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'URL', 'text' => 'View order', 'url' => 'https://cutt.ly/{{1}}', 'example' => ['https://cutt.ly/abc123'] }
            ]
          }
        ],
        variable_mapping: {
          '1' => 'customer.first',
          '2' => 'order.id',
          '3' => 'order.items_count',
          '4' => 'store.name'
        },
        url_button: { 'mode' => 'predefined', 'variable' => 'order.status_url', 'text' => 'View order' }
      },
      {
        key: 'order_confirmation_with_shipping',
        title: 'Order confirmation — with shipping address',
        description: 'Image-headered confirmation that echoes the shipping address back to the buyer. Cuts "wrong address" support tickets — buyers spot mistakes immediately.',
        category: 'UTILITY',
        event_type_key: 'order_created',
        tags: %w[transactional shipping-address support-deflection image],
        language: 'en_US',
        name_suggestion: 'order_confirmation_shipping_v1',
        components: [
          { 'type' => 'HEADER', 'format' => 'IMAGE' },
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, thanks for your order *{{2}}* from {{3}}! 🎉\n\nWe'll ship it to:\n📍 *{{4}}*\n\nIf anything looks off, tap below to view the order — you can update the address until it ships.",
            'example' => { 'body_text' => [['Aman', '#1023', 'MyShop', '12 MG Rd, Mumbai 400001, IN']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'URL', 'text' => 'View order', 'url' => 'https://cutt.ly/{{1}}', 'example' => ['https://cutt.ly/abc123'] }
            ]
          }
        ],
        variable_mapping: {
          '1' => 'customer.first',
          '2' => 'order.id',
          '3' => 'store.name',
          '4' => 'order.shipping_address'
        },
        url_button: { 'mode' => 'predefined', 'variable' => 'order.status_url', 'text' => 'View order' }
      },
      {
        key: 'order_confirmation_premium',
        title: 'Order confirmation — premium (full details)',
        description: 'The highest-context confirmation. Image header, items count, order total, and shipping address. Best for fraud-conscious markets and high-AOV stores.',
        category: 'UTILITY',
        event_type_key: 'order_created',
        tags: %w[transactional premium full-details image],
        language: 'en_US',
        name_suggestion: 'order_confirmation_premium_v1',
        components: [
          { 'type' => 'HEADER', 'format' => 'IMAGE' },
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, your order *{{2}}* is confirmed! 🎉\n\n• Items: *{{3}}*\n• Total: *{{4}}*\n• Shipping to: {{5}}\n\nThanks for shopping with {{6}}. We'll send tracking as soon as it ships.",
            'example' => { 'body_text' => [['Aman', '#1023', '3', '₹2,499', '12 MG Rd, Mumbai 400001, IN', 'MyShop']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'URL', 'text' => 'View order', 'url' => 'https://cutt.ly/{{1}}', 'example' => ['https://cutt.ly/abc123'] }
            ]
          }
        ],
        variable_mapping: {
          '1' => 'customer.first',
          '2' => 'order.id',
          '3' => 'order.items_count',
          '4' => 'order.total',
          '5' => 'order.shipping_address',
          '6' => 'store.name'
        },
        url_button: { 'mode' => 'predefined', 'variable' => 'order.status_url', 'text' => 'View order' }
      },
      {
        key: 'order_confirmation_minimal',
        title: 'Order confirmation — one-liner',
        description: 'Single-sentence confirmation, no image. Highest read-through on small screens.',
        category: 'UTILITY',
        event_type_key: 'order_created',
        tags: %w[transactional minimal no-image],
        language: 'en_US',
        name_suggestion: 'order_confirmation_minimal_v1',
        components: [
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, your order *{{2}}* is confirmed. We'll send tracking as soon as it ships. 📦",
            'example' => { 'body_text' => [['Aman', '#1023']] }
          },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'URL', 'text' => 'View order', 'url' => 'https://cutt.ly/{{1}}', 'example' => ['https://cutt.ly/abc123'] }
            ]
          }
        ],
        variable_mapping: { '1' => 'customer.first', '2' => 'order.id' },
        url_button: { 'mode' => 'predefined', 'variable' => 'order.status_url', 'text' => 'View order' }
      },

      # ─────────────────────────────────────────────────────────────────────
      # ORDER FULFILLED — order_fulfilled
      # ─────────────────────────────────────────────────────────────────────
      {
        key: 'order_shipped_concise',
        title: 'Order shipped — text only',
        description: 'Plain text shipment notification, no image. Use if you don\'t have a tracking banner ready.',
        category: 'UTILITY',
        event_type_key: 'order_fulfilled',
        tags: %w[transactional minimal no-image],
        language: 'en_US',
        name_suggestion: 'order_shipped_concise_v1',
        components: [
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, your order *{{2}}* just shipped! Tap below to follow it 🚚",
            'example' => { 'body_text' => [['Aman', '#1023']] }
          },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'URL', 'text' => 'Track package', 'url' => 'https://cutt.ly/{{1}}', 'example' => ['https://cutt.ly/abc123'] }
            ]
          }
        ],
        variable_mapping: { '1' => 'customer.first', '2' => 'order.id' },
        url_button: { 'mode' => 'predefined', 'variable' => 'tracking.url', 'fallback_variable' => 'order.status_url', 'text' => 'Track package' }
      },
      {
        key: 'order_shipped_tracking',
        title: 'Order shipped — with tracking details',
        description: 'Image header + carrier and tracking number in the body. Solid default for stores that have working carrier integrations.',
        category: 'UTILITY',
        event_type_key: 'order_fulfilled',
        tags: %w[transactional tracking image],
        language: 'en_US',
        name_suggestion: 'order_shipped_tracking_v1',
        components: [
          { 'type' => 'HEADER', 'format' => 'IMAGE' },
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, your order *{{2}}* has shipped via *{{3}}*! 🚚\n\nTracking: *{{4}}*\n\nTap below to follow it in real time.",
            'example' => { 'body_text' => [['Aman', '#1023', 'BlueDart', 'BD9183471']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Questions? Just reply to this message.' },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'URL', 'text' => 'Track package', 'url' => 'https://cutt.ly/{{1}}', 'example' => ['https://cutt.ly/abc123'] }
            ]
          }
        ],
        variable_mapping: {
          '1' => 'customer.first',
          '2' => 'order.id',
          '3' => 'tracking.carrier',
          '4' => 'tracking.number'
        },
        url_button: { 'mode' => 'predefined', 'variable' => 'tracking.url', 'fallback_variable' => 'order.status_url', 'text' => 'Track package' }
      },
      {
        key: 'order_shipped_to_address',
        title: 'Order shipped — to shipping address',
        description: 'Image header + tracking + the destination address. Reassures buyers their package is on its way to the right place.',
        category: 'UTILITY',
        event_type_key: 'order_fulfilled',
        tags: %w[transactional shipping-address tracking image],
        language: 'en_US',
        name_suggestion: 'order_shipped_to_address_v1',
        components: [
          { 'type' => 'HEADER', 'format' => 'IMAGE' },
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, your order *{{2}}* is on its way! 📦\n\nShipping to:\n📍 {{3}}\n\nTracking: *{{4}}*\n\nWe'll keep you posted.",
            'example' => { 'body_text' => [['Aman', '#1023', '12 MG Rd, Mumbai 400001, IN', 'BD9183471']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Questions? Just reply.' },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'URL', 'text' => 'Track package', 'url' => 'https://cutt.ly/{{1}}', 'example' => ['https://cutt.ly/abc123'] }
            ]
          }
        ],
        variable_mapping: {
          '1' => 'customer.first',
          '2' => 'order.id',
          '3' => 'order.shipping_address',
          '4' => 'tracking.number'
        },
        url_button: { 'mode' => 'predefined', 'variable' => 'tracking.url', 'fallback_variable' => 'order.status_url', 'text' => 'Track package' }
      },
      {
        key: 'order_shipped_premium',
        title: 'Order shipped — premium (full details)',
        description: 'Image + carrier + tracking + delivery address. The maximum-context shipped notification.',
        category: 'UTILITY',
        event_type_key: 'order_fulfilled',
        tags: %w[transactional premium full-details image],
        language: 'en_US',
        name_suggestion: 'order_shipped_premium_v1',
        components: [
          { 'type' => 'HEADER', 'format' => 'IMAGE' },
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, your order *{{2}}* has shipped! 🚚\n\n• Carrier: *{{3}}*\n• Tracking: *{{4}}*\n• Delivering to: {{5}}\n\nThanks for shopping with {{6}} — we'll keep you posted!",
            'example' => { 'body_text' => [['Aman', '#1023', 'BlueDart', 'BD9183471', '12 MG Rd, Mumbai 400001, IN', 'MyShop']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Questions? Just reply.' },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'URL', 'text' => 'Track package', 'url' => 'https://cutt.ly/{{1}}', 'example' => ['https://cutt.ly/abc123'] }
            ]
          }
        ],
        variable_mapping: {
          '1' => 'customer.first',
          '2' => 'order.id',
          '3' => 'tracking.carrier',
          '4' => 'tracking.number',
          '5' => 'order.shipping_address',
          '6' => 'store.name'
        },
        url_button: { 'mode' => 'predefined', 'variable' => 'tracking.url', 'fallback_variable' => 'order.status_url', 'text' => 'Track package' }
      },

      # ─────────────────────────────────────────────────────────────────────
      # ABANDONED CART — abandoned_cart
      # ─────────────────────────────────────────────────────────────────────
      {
        key: 'abandoned_cart_simple',
        title: 'Abandoned cart — gentle nudge (text)',
        description: 'Simple text reminder, no discount, no image. Best as Stage 1 (~30 min after abandon) so a discount-savvy buyer doesn\'t learn to abandon for the offer.',
        category: 'UTILITY',
        event_type_key: 'abandoned_cart',
        tags: %w[transactional recovery no-image],
        language: 'en_US',
        name_suggestion: 'abandoned_cart_v1',
        components: [
          {
            'type' => 'BODY',
            'text' => "Hey {{1}}, you left {{2}} item(s) in your cart at {{3}}.\n\nThey're still waiting for you — tap below to complete your order.",
            'example' => { 'body_text' => [['Aman', '2', 'MyShop']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'URL', 'text' => 'Complete checkout', 'url' => 'https://cutt.ly/{{1}}', 'example' => ['https://cutt.ly/abc123'] }
            ]
          }
        ],
        variable_mapping: { '1' => 'customer.first', '2' => 'cart.items_count', '3' => 'store.name' },
        url_button: { 'mode' => 'predefined', 'variable' => 'cart.recovery_url', 'text' => 'Complete checkout' }
      },
      {
        key: 'abandoned_cart_with_image',
        title: 'Abandoned cart — product image, no discount',
        description: 'Image header — pick "Use the order\'s product image" so each customer sees the actual item they left behind. Strong recall; no discount.',
        category: 'UTILITY',
        event_type_key: 'abandoned_cart',
        tags: %w[transactional recovery image],
        language: 'en_US',
        name_suggestion: 'abandoned_cart_image_v1',
        components: [
          { 'type' => 'HEADER', 'format' => 'IMAGE' },
          {
            'type' => 'BODY',
            'text' => "Hey {{1}}, you left {{2}} item(s) in your cart at {{3}}.\n\nStill thinking it over? Your total is *{{4}}* — tap below to pick up where you left off.",
            'example' => { 'body_text' => [['Aman', '2', 'MyShop', '₹2,499']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'URL', 'text' => 'Complete checkout', 'url' => 'https://cutt.ly/{{1}}', 'example' => ['https://cutt.ly/abc123'] }
            ]
          }
        ],
        variable_mapping: {
          '1' => 'customer.first',
          '2' => 'cart.items_count',
          '3' => 'store.name',
          '4' => 'cart.total'
        },
        url_button: { 'mode' => 'predefined', 'variable' => 'cart.recovery_url', 'text' => 'Complete checkout' }
      },
      {
        key: 'abandoned_cart_with_discount_image',
        title: 'Abandoned cart — image + discount code',
        description: 'Stage 2 (~24h). Image header + dynamic discount. Reads the code from your stage\'s discount config (static or auto-generated). Meta typically auto-upgrades to MARKETING during review.',
        category: 'UTILITY',
        event_type_key: 'abandoned_cart',
        tags: %w[transactional recovery incentive discount image],
        language: 'en_US',
        name_suggestion: 'abandoned_cart_discount_image_v1',
        components: [
          { 'type' => 'HEADER', 'format' => 'IMAGE' },
          {
            'type' => 'BODY',
            'text' => "Hey {{1}}, you left {{2}} item(s) in your cart at {{3}}.\n\nFinish your order in the next 24 hours and we'll give you *{{4}}* — use code *{{5}}* at checkout.",
            'example' => { 'body_text' => [['Aman', '2', 'MyShop', '10% off', 'COMEBACK10']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'URL', 'text' => 'Complete checkout', 'url' => 'https://cutt.ly/{{1}}', 'example' => ['https://cutt.ly/abc123'] }
            ]
          }
        ],
        variable_mapping: {
          '1' => 'customer.first',
          '2' => 'cart.items_count',
          '3' => 'store.name',
          '4' => 'discount.formatted',
          '5' => 'discount.code'
        },
        url_button: { 'mode' => 'predefined', 'variable' => 'cart.recovery_url', 'text' => 'Complete checkout' }
      },
      {
        key: 'abandoned_cart_urgency_image',
        title: 'Abandoned cart — final urgency + image',
        description: 'Stage 3 (~72h). Image header + last-call wording + bigger discount. Pair with a larger `discount.value` on the binding.',
        category: 'UTILITY',
        event_type_key: 'abandoned_cart',
        tags: %w[transactional recovery urgency discount image],
        language: 'en_US',
        name_suggestion: 'abandoned_cart_urgency_image_v1',
        components: [
          { 'type' => 'HEADER', 'format' => 'IMAGE' },
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, last call on your cart at {{2}} — stock is limited and we can't hold it forever. ⏰\n\nUse code *{{3}}* in the next 24 hours for *{{4}}* off.",
            'example' => { 'body_text' => [['Aman', 'MyShop', 'LAST15', '15%']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'URL', 'text' => 'Grab my cart', 'url' => 'https://cutt.ly/{{1}}', 'example' => ['https://cutt.ly/abc123'] }
            ]
          }
        ],
        variable_mapping: {
          '1' => 'customer.first',
          '2' => 'store.name',
          '3' => 'discount.code',
          '4' => 'discount.value'
        },
        url_button: { 'mode' => 'predefined', 'variable' => 'cart.recovery_url', 'text' => 'Grab my cart' }
      },
      {
        key: 'abandoned_cart_premium',
        title: 'Abandoned cart — premium (image + details + discount)',
        description: 'Maximum-context recovery message. Image header, cart total, discount code, formatted discount. Best as the second or third stage when you want to pull out all stops.',
        category: 'UTILITY',
        event_type_key: 'abandoned_cart',
        tags: %w[transactional recovery premium discount image],
        language: 'en_US',
        name_suggestion: 'abandoned_cart_premium_v1',
        components: [
          { 'type' => 'HEADER', 'format' => 'IMAGE' },
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, your cart at {{2}} is still waiting — *{{3}} item(s) for {{4}}*. 🛒\n\nSweetener: use code *{{5}}* for *{{6}}* if you finish checkout in the next 24 hours.",
            'example' => { 'body_text' => [['Aman', 'MyShop', '2', '₹2,499', 'COMEBACK10', '10% off']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'URL', 'text' => 'Complete checkout', 'url' => 'https://cutt.ly/{{1}}', 'example' => ['https://cutt.ly/abc123'] }
            ]
          }
        ],
        variable_mapping: {
          '1' => 'customer.first',
          '2' => 'store.name',
          '3' => 'cart.items_count',
          '4' => 'cart.total',
          '5' => 'discount.code',
          '6' => 'discount.formatted'
        },
        url_button: { 'mode' => 'predefined', 'variable' => 'cart.recovery_url', 'text' => 'Complete checkout' }
      },

      # ─────────────────────────────────────────────────────────────────────
      # FIRST-TIME PURCHASE — first_time_purchase
      # Customer-focused, NOT order-detail-focused. The order_created
      # automation already covers the order specifics; first-time-purchase
      # is the brand introduction moment.
      # ─────────────────────────────────────────────────────────────────────
      {
        key: 'first_purchase_welcome',
        title: 'First-time customer — branded welcome',
        description: 'Image-headered welcome message focused on the customer and the brand — no order details. Ideal for the buyer\'s first impression of your WhatsApp channel.',
        category: 'UTILITY',
        event_type_key: 'first_time_purchase',
        tags: %w[lifecycle welcome image],
        language: 'en_US',
        name_suggestion: 'first_purchase_welcome_v1',
        components: [
          { 'type' => 'HEADER', 'format' => 'IMAGE' },
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, welcome to {{2}}! 💜\n\nWe're so glad you found us. Look out for messages here for shipping updates, exclusive drops, and the occasional behind-the-scenes peek.",
            'example' => { 'body_text' => [['Aman', 'MyShop']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' }
        ],
        variable_mapping: { '1' => 'customer.first', '2' => 'store.name' },
        url_button: nil
      },
      {
        key: 'first_purchase_thank_you',
        title: 'First-time customer — thank you (text)',
        description: 'Plain-text thank-you, no image, no order details. Smallest payload — fastest to approve and ship.',
        category: 'UTILITY',
        event_type_key: 'first_time_purchase',
        tags: %w[lifecycle thank-you no-image],
        language: 'en_US',
        name_suggestion: 'first_purchase_thank_you_v1',
        components: [
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, thank you for choosing {{2}}! 💜\n\nWe really appreciate it — and we'd love to see you again.",
            'example' => { 'body_text' => [['Aman', 'MyShop']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' }
        ],
        variable_mapping: { '1' => 'customer.first', '2' => 'store.name' },
        url_button: nil
      },
      {
        key: 'first_purchase_discount_offer',
        title: 'First-time customer — repeat-purchase incentive',
        description: 'Image header + a static discount nudge for the customer\'s NEXT order. Drives second-purchase conversion. Edit the body to set your code.',
        category: 'UTILITY',
        event_type_key: 'first_time_purchase',
        tags: %w[lifecycle incentive image marketing-leaning],
        language: 'en_US',
        name_suggestion: 'first_purchase_repeat_v1',
        components: [
          { 'type' => 'HEADER', 'format' => 'IMAGE' },
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, thanks for shopping with {{2}}! 💜\n\nAs a small thank-you, use *FIRST10* for *10% off* on your next order. We hope to see you again soon!",
            'example' => { 'body_text' => [['Aman', 'MyShop']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' }
        ],
        variable_mapping: { '1' => 'customer.first', '2' => 'store.name' },
        url_button: nil
      },
      {
        key: 'first_purchase_brand_intro',
        title: 'First-time customer — brand intro',
        description: 'Image header + warm intro to who you are and what to expect from your WhatsApp channel. Sets clear expectations and reduces opt-outs downstream.',
        category: 'UTILITY',
        event_type_key: 'first_time_purchase',
        tags: %w[lifecycle brand-intro image],
        language: 'en_US',
        name_suggestion: 'first_purchase_brand_intro_v1',
        components: [
          { 'type' => 'HEADER', 'format' => 'IMAGE' },
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, welcome to the {{2}} family! 🎉\n\nWe'll only message you for: order updates, shipping notifications, and the occasional new-launch heads-up. That's it — no spam.",
            'example' => { 'body_text' => [['Aman', 'MyShop']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' }
        ],
        variable_mapping: { '1' => 'customer.first', '2' => 'store.name' },
        url_button: nil
      },

      # ─────────────────────────────────────────────────────────────────────
      # COD VERIFICATION — cod_verification
      # Quick-reply payloads (cod_confirm / cod_cancel) are fixed; labels
      # are merchant-editable but the underlying payload routing depends on
      # those exact strings.
      # ─────────────────────────────────────────────────────────────────────
      {
        key: 'cod_verification_confirm_cancel',
        title: 'COD verification — Confirm / Cancel (text)',
        description: 'Plain-text COD verification with two quick-reply buttons. Cancel auto-cancels the Shopify order.',
        category: 'UTILITY',
        event_type_key: 'cod_verification',
        tags: %w[transactional cod verification no-image],
        language: 'en_US',
        name_suggestion: 'cod_verification_v1',
        components: [
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, please confirm your COD order *{{2}}* for {{3}}.\n\nTap *Confirm* below to keep the order, or *Cancel* if it was placed by mistake.",
            'example' => { 'body_text' => [['Aman', '#1023', '₹2,499']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'QUICK_REPLY', 'text' => 'Confirm' },
              { 'type' => 'QUICK_REPLY', 'text' => 'Cancel' }
            ]
          }
        ],
        variable_mapping: { '1' => 'customer.first', '2' => 'order.id', '3' => 'order.total' },
        url_button: nil
      },
      {
        key: 'cod_verification_with_address',
        title: 'COD verification — with shipping address',
        description: 'Image header + Confirm/Cancel + the shipping address echoed back to the buyer. Cuts wrong-address failures by giving buyers one last chance to spot a typo.',
        category: 'UTILITY',
        event_type_key: 'cod_verification',
        tags: %w[transactional cod verification shipping-address image],
        language: 'en_US',
        name_suggestion: 'cod_verification_address_v1',
        components: [
          { 'type' => 'HEADER', 'format' => 'IMAGE' },
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, please confirm your COD order *{{2}}* for {{3}}.\n\nWe'll deliver to:\n📍 {{4}}\n\nTap *Confirm* to proceed or *Cancel* if it was placed by mistake.",
            'example' => { 'body_text' => [['Aman', '#1023', '₹2,499', '12 MG Rd, Mumbai 400001, IN']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'QUICK_REPLY', 'text' => 'Confirm' },
              { 'type' => 'QUICK_REPLY', 'text' => 'Cancel' }
            ]
          }
        ],
        variable_mapping: {
          '1' => 'customer.first',
          '2' => 'order.id',
          '3' => 'order.total',
          '4' => 'order.shipping_address'
        },
        # Send the order's product image as the header by default (falls back to
        # the store logo when an order has no resolvable product image).
        header_media: { 'format' => 'IMAGE', 'mode' => 'order_product_image' },
        url_button: nil
      },
      {
        key: 'cod_verification_premium',
        title: 'COD verification — premium (full details)',
        description: 'Image + items count + total + shipping address + Confirm/Cancel. The highest-context COD verification — gives the buyer everything they need to decide in one screen.',
        category: 'UTILITY',
        event_type_key: 'cod_verification',
        tags: %w[transactional cod verification premium image],
        language: 'en_US',
        name_suggestion: 'cod_verification_premium_v1',
        components: [
          { 'type' => 'HEADER', 'format' => 'IMAGE' },
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, please confirm your COD order *{{2}}*.\n\n• Items: *{{3}}*\n• Total: *{{4}}*\n• Delivering to: {{5}}\n\nTap *Confirm* to keep it, or *Cancel* if there's a mistake.",
            'example' => { 'body_text' => [['Aman', '#1023', '3', '₹2,499', '12 MG Rd, Mumbai 400001, IN']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'QUICK_REPLY', 'text' => 'Confirm' },
              { 'type' => 'QUICK_REPLY', 'text' => 'Cancel' }
            ]
          }
        ],
        variable_mapping: {
          '1' => 'customer.first',
          '2' => 'order.id',
          '3' => 'order.items_count',
          '4' => 'order.total',
          '5' => 'order.shipping_address'
        },
        # Send the order's product image as the header by default (falls back to
        # the store logo when an order has no resolvable product image).
        header_media: { 'format' => 'IMAGE', 'mode' => 'order_product_image' },
        url_button: nil
      },

      # ─────────────────────────────────────────────────────────────────────
      # PRE-ORDER OTP — pre_order_otp
      # AUTHENTICATION category is Meta-managed; merchant only picks the name.
      # ─────────────────────────────────────────────────────────────────────
      {
        key: 'pre_order_otp_authentication',
        title: 'OTP verification code',
        description: 'One-time passcode for pre-order / COD verification. Authentication category — highest deliverability and the only Meta-compliant way to send codes.',
        category: 'AUTHENTICATION',
        event_type_key: 'pre_order_otp',
        tags: %w[authentication otp],
        language: 'en_US',
        name_suggestion: 'pre_order_otp_v1',
        components: [
          { 'type' => 'BODY', 'add_security_recommendation' => true },
          { 'type' => 'FOOTER', 'code_expiration_minutes' => 5 },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'OTP', 'otp_type' => 'COPY_CODE', 'text' => 'Copy code' }
            ]
          }
        ],
        variable_mapping: { '1' => 'otp.code' },
        url_button: nil
      },

      {
        key: 'campaign_winback_offer',
        title: 'Win back lapsed customers',
        description: 'Offer for customers who have not ordered in a while. Text only, so approval is quick.',
        category: 'MARKETING',
        event_type_key: 'campaign_broadcast',
        tags: %w[campaign winback no-image],
        language: 'en_US',
        name_suggestion: 'campaign_winback_offer_v1',
        components: [
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, we miss you at {{2}}! 💛\n\nIt's been a while since your last order, so here's something just for you: *{{3}}*.\n\nVisit our store to see what's new.",
            'example' => { 'body_text' => [['Aman', 'MyShop', '10% off with code COMEBACK10']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' }
        ],
        variable_mapping: { '1' => 'recipient.name' },
        url_button: nil
      },
      {
        key: 'campaign_festive_offer',
        title: 'Festive sale announcement',
        description: 'Announce a festive or seasonal sale to everyone subscribed. Text only, so approval is quick.',
        category: 'MARKETING',
        event_type_key: 'campaign_broadcast',
        tags: %w[campaign festive sale no-image],
        language: 'en_US',
        name_suggestion: 'campaign_festive_offer_v1',
        components: [
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, the festive sale is live at {{2}}! 🎉\n\nGet *{{3}}* on your favourites, for a limited time.\n\nVisit our store before the offer ends.",
            'example' => { 'body_text' => [['Aman', 'MyShop', 'flat 20% off']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' }
        ],
        variable_mapping: { '1' => 'recipient.name' },
        url_button: nil
      },
      {
        key: 'campaign_prepaid_nudge',
        title: 'Pay online next time',
        description: 'Encourage cash-on-delivery buyers to pay online on their next order. Text only, so approval is quick.',
        category: 'MARKETING',
        event_type_key: 'campaign_broadcast',
        tags: %w[campaign prepaid cod no-image],
        language: 'en_US',
        name_suggestion: 'campaign_prepaid_nudge_v1',
        components: [
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, thanks for shopping with {{2}}!\n\nOn your next order, pay online and get *{{3}}*. Paying online is quick and safe.\n\nWe look forward to seeing you again.",
            'example' => { 'body_text' => [['Aman', 'MyShop', '5% off']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' }
        ],
        variable_mapping: { '1' => 'recipient.name' },
        url_button: nil
      },
      # The checkout link is a body variable, not a URL button: campaign buttons
      # send the raw field as the cutt.ly slug, and a full recovery URL is not one.
      {
        key: 'campaign_cart_recovery',
        title: 'Finish your order',
        description: 'Reminder for shoppers who left a checkout, with a link back to it. Text only, so approval is quick.',
        category: 'MARKETING',
        event_type_key: 'campaign_broadcast',
        tags: %w[campaign recovery no-image],
        language: 'en_US',
        name_suggestion: 'campaign_cart_recovery_v1',
        components: [
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, you left something in your cart at {{2}}.\n\nFinish your order here: {{3}}\n\nItems in your cart may sell out soon.",
            'example' => { 'body_text' => [['Aman', 'MyShop', 'https://myshop.com/checkouts/abc123']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' }
        ],
        variable_mapping: { '1' => 'recipient.name' },
        url_button: nil
      },

      {
        key: 'cod_verification_reminder_v1',
        title: 'COD reminder — Confirm / Cancel',
        description: 'Reminder for customers who have not answered the COD verification. Same Confirm / Cancel buttons.',
        category: 'UTILITY',
        event_type_key: 'cod_verification_reminder',
        tags: %w[transactional cod verification reminder no-image],
        language: 'en_US',
        name_suggestion: 'cod_verification_reminder_v1',
        components: [
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, your COD order *{{2}}* for {{3}} is waiting for your confirmation.\n\nTap *Confirm* so we can ship it, or *Cancel* if you no longer need it.",
            'example' => { 'body_text' => [['Aman', '#1023', '₹2,499']] }
          },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'QUICK_REPLY', 'text' => 'Confirm' },
              { 'type' => 'QUICK_REPLY', 'text' => 'Cancel' }
            ]
          }
        ],
        variable_mapping: { '1' => 'customer.first', '2' => 'order.id', '3' => 'order.total' },
        url_button: nil
      },
      {
        key: 'order_cancelled_v1',
        title: 'Order cancelled',
        description: 'Tells the customer their order was cancelled and why.',
        category: 'UTILITY',
        event_type_key: 'order_cancelled',
        tags: %w[transactional cancelled no-image],
        language: 'en_US',
        name_suggestion: 'order_cancelled_v1',
        components: [
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, your order *{{2}}* from {{3}} has been cancelled.\n\nReason: {{4}}\n\nReply to this message if you have any questions.",
            'example' => { 'body_text' => [['Aman', '#1023', 'MyShop', 'Item out of stock']] }
          }
        ],
        variable_mapping: { '1' => 'customer.first', '2' => 'order.id', '3' => 'store.name', '4' => 'order.cancel_reason' },
        url_button: nil
      },
      {
        key: 'order_out_for_delivery_v1',
        title: 'Out for delivery — with tracking',
        description: 'Lets the customer know the package arrives today, with a tracking button. Keep cash ready for COD orders.',
        category: 'UTILITY',
        event_type_key: 'order_out_for_delivery',
        tags: %w[transactional delivery tracking no-image],
        language: 'en_US',
        name_suggestion: 'order_out_for_delivery_v1',
        components: [
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, your order *{{2}}* is out for delivery today 🚚\n\nPlease keep {{3}} ready if you chose cash on delivery.",
            'example' => { 'body_text' => [['Aman', '#1023', '₹2,499']] }
          },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'URL', 'text' => 'Track package', 'url' => 'https://cutt.ly/{{1}}', 'example' => ['https://cutt.ly/abc123'] }
            ]
          }
        ],
        variable_mapping: { '1' => 'customer.first', '2' => 'order.id', '3' => 'order.total' },
        url_button: { 'mode' => 'predefined', 'variable' => 'tracking.url', 'fallback_variable' => 'order.status_url', 'text' => 'Track package' }
      },
      {
        key: 'order_delivered_v1',
        title: 'Order delivered',
        description: 'Confirms delivery and invites the customer to reply if anything is wrong.',
        category: 'UTILITY',
        event_type_key: 'order_delivered',
        tags: %w[transactional delivery no-image],
        language: 'en_US',
        name_suggestion: 'order_delivered_v1',
        components: [
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, your order *{{2}}* has been delivered. 📦\n\nIf anything is missing or not right, reply here and we'll help.",
            'example' => { 'body_text' => [['Aman', '#1023']] }
          }
        ],
        variable_mapping: { '1' => 'customer.first', '2' => 'order.id' },
        url_button: nil
      },
      {
        key: 'feedback_request_v1',
        title: 'Feedback request — quick replies',
        description: 'Asks how the order was. Replies land in your inbox, where the AI agent or your team can follow up.',
        category: 'UTILITY',
        event_type_key: 'feedback_request',
        tags: %w[feedback post-purchase no-image],
        language: 'en_US',
        name_suggestion: 'feedback_request_v1',
        components: [
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, how was your order *{{2}}* from {{3}}?\n\nTap a button below. It takes a second and helps us a lot.",
            'example' => { 'body_text' => [['Aman', '#1023', 'MyShop']] }
          },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'QUICK_REPLY', 'text' => 'Loved it' },
              { 'type' => 'QUICK_REPLY', 'text' => 'It was okay' },
              { 'type' => 'QUICK_REPLY', 'text' => 'Had a problem' }
            ]
          }
        ],
        variable_mapping: { '1' => 'customer.first', '2' => 'order.id', '3' => 'store.name' },
        url_button: nil
      },
      {
        key: 'reorder_reminder_v1',
        title: 'Reorder reminder — shop button',
        description: 'Reminds the customer to buy again, with a button to your store.',
        category: 'MARKETING',
        event_type_key: 'reorder_reminder',
        tags: %w[marketing reorder retention no-image],
        language: 'en_US',
        name_suggestion: 'reorder_reminder_v1',
        components: [
          {
            'type' => 'BODY',
            'text' => "Hi {{1}}, running low on {{2}}?\n\nReorder from {{3}} in a few taps.",
            'example' => { 'body_text' => [['Aman', 'Product 1 : Qty 1', 'MyShop']] }
          },
          { 'type' => 'FOOTER', 'text' => 'Reply STOP to opt out.' },
          {
            'type' => 'BUTTONS',
            'buttons' => [
              { 'type' => 'URL', 'text' => 'Shop again', 'url' => 'https://cutt.ly/{{1}}', 'example' => ['https://cutt.ly/abc123'] }
            ]
          }
        ],
        variable_mapping: { '1' => 'customer.first', '2' => 'order.products', '3' => 'store.name' },
        url_button: { 'mode' => 'predefined', 'variable' => 'store.url', 'text' => 'Shop again' }
      },

    ].freeze

    def self.all
      ENTRIES
    end

    def self.find(key)
      ENTRIES.find { |e| e[:key] == key.to_s }
    end

    def self.as_json
      ENTRIES.map do |e|
        {
          key: e[:key],
          title: e[:title],
          description: e[:description],
          category: e[:category],
          event_type_key: e[:event_type_key],
          tags: e[:tags],
          language: e[:language],
          name_suggestion: e[:name_suggestion],
          components: e[:components],
          variable_mapping: e[:variable_mapping],
          url_button: e[:url_button],
          header_media: header_media_for(e)
        }
      end
    end

    # An IMAGE header with no media source reaches Meta with nothing to render
    # and gets replaced by the branded default image. Default such templates to
    # the order's product image so the buyer sees what they bought.
    def self.header_media_for(entry)
      return entry[:header_media] if entry[:header_media].present?
      return nil unless image_header?(entry)

      { 'format' => 'IMAGE', 'mode' => 'order_product_image' }
    end

    def self.image_header?(entry)
      Array(entry[:components]).any? do |c|
        c.is_a?(Hash) &&
          c['type'].to_s.casecmp?('HEADER') &&
          c['format'].to_s.casecmp?('IMAGE')
      end
    end
  end
end
