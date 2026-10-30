# frozen_string_literal: true

module Whatsapp
  module Ai
    class Tools
      INTENTS = %w[order_status cod_confirmation product_question store_faq payment discount greeting other].freeze
      HANDOFF_REASONS = %w[cancel_request return_refund address_change complaint human_requested media payment_issue
                           unsure other].freeze
      TERMINAL = %w[reply handoff].freeze
      REPLY_LIMIT = 1000

      Outcome = Struct.new(:kind, :text, :intent, :reason, :note, keyword_init: true)

      attr_reader :actions

      def initialize(conversation:, setting:, context:, dry_run: false, allow_actions: true)
        @conversation = conversation
        @setting = setting
        @context = context
        @dry_run = dry_run
        @allow_actions = allow_actions
        @shop = conversation.shop
        @actions = []
      end

      def definitions
        @definitions ||= build_definitions
      end

      def build_definitions
        defs = [reply_def, handoff_def]
        defs << lookup_order_def if @setting.skill?('order_status')
        defs << search_products_def if @setting.skill?('product_help')
        return defs unless @allow_actions

        if @setting.skill?('cod_confirmation')
          defs << order_def('confirm_cod_order', 'Confirm a cash-on-delivery order that is awaiting confirmation, after the customer clearly agrees. Returns why if it cannot.')
          if @setting.allow_cancel
            defs << order_def('cancel_cod_order', 'Cancel a cash-on-delivery order (pending or confirmed, not yet shipped) when the customer clearly asks to cancel it.')
          end
        end
        if @setting.skill?('pay_online')
          defs << order_def('send_payment_link', 'Send the online payment link for a COD order when the customer wants to pay online. Returns the reason if the order is not eligible.')
        end
        defs << discount_def if @setting.skill?('discounts')
        defs << place_order_def if @setting.skill?('place_orders')
        defs
      end

      def names
        definitions.map { |d| d[:function][:name] }
      end

      def execute(name, raw_args)
        return { 'ok' => false, 'error' => "Tool #{name} is not available. Hand off." } unless names.include?(name)

        args = parse_args(raw_args)
        case name
        when 'reply'
          Outcome.new(kind: :reply, text: args['text'].to_s.strip.first(REPLY_LIMIT),
                      intent: INTENTS.include?(args['intent']) ? args['intent'] : 'other')
        when 'handoff'
          if args['reason'] == 'cancel_request' && names.include?('cancel_cod_order') && !@cancel_attempted
            @cancel_attempted = true
            return { 'ok' => false, 'error' => 'Do not hand off: cancelling is enabled. If you know the order number, call cancel_cod_order with it now. If not, use reply to ask for the order number. Hand off only if cancel_cod_order fails.' }
          end

          Outcome.new(kind: :handoff, text: args['customer_message'].to_s.strip.first(REPLY_LIMIT),
                      reason: HANDOFF_REASONS.include?(args['reason']) ? args['reason'] : 'other',
                      note: args['note'].to_s.strip.first(500), intent: 'other')
        when 'search_products' then search_products(args['query'])
        when 'lookup_order' then lookup_order(args['order_number'], args['order_phone'])
        when 'confirm_cod_order' then confirm_order(args['order_number'])
        when 'cancel_cod_order' then cancel_order(args['order_number'])
        when 'send_payment_link' then payment_link(args['order_number'])
        when 'get_discount_code' then discount_code
        when 'place_cod_order' then place_order(args)
        else { 'ok' => false, 'error' => "Unknown tool #{name}" }
        end
      rescue StandardError => e
        Rails.logger.error("[Whatsapp::Ai::Tools] #{name} failed conv=#{@conversation.id}: #{e.class}: #{e.message}")
        record(name, ok: false, error: e.class.name)
        { 'ok' => false, 'error' => 'That action failed. Hand off to the team.' }
      end

      private

      def parse_args(raw)
        return raw if raw.is_a?(Hash)

        JSON.parse(raw.to_s.presence || '{}')
      rescue JSON::ParserError
        {}
      end

      def record(type, **attrs)
        @actions << { 'type' => type }.merge(attrs.transform_keys(&:to_s)).merge(@dry_run ? { 'dry_run' => true } : {})
      end

      def orders
        Array(@context['_orders'])
      end

      def awaiting_orders
        orders.select { |oc| oc.is_cod_order == true && ContextBuilder::AWAITING.include?(oc.status.to_s) }
      end

      def paylink_orders
        orders.select { |oc| Whatsapp::Inbox::PaymentLinkSender.order_reason(oc).nil? }
      end

      def find_order(number, pool)
        digits = number.to_s.gsub(/\D/, '')
        return nil if digits.blank?

        pool.find { |oc| oc.order_number.to_s.gsub(/\D/, '') == digits }
      end

      # Pulls an order the customer named into CONTEXT when it was placed from this same phone,
      # so actions work without a separate lookup_order step.
      def load_own_order(number)
        digits = number.to_s.gsub(/\D/, '')
        return nil if digits.blank? || digits.length > 15
        return find_order(digits, orders) if find_order(digits, orders)

        scope = OrderConfirmation.where(shop_id: @shop.id)
        oc = scope.where(order_number: [digits, "##{digits}"]).order(created_at: :desc).first ||
             scope.where("regexp_replace(coalesce(order_number, ''), '\\D', '', 'g') = ?", digits).order(created_at: :desc).first
        return nil unless oc
        return nil unless Whatsapp::Inbox::OrderLookup.last10(oc.customer_number) == @conversation.phone_last10.to_s

        @context['_orders'] = (orders + [oc]).uniq(&:id)
        oc
      end

      def label(oc)
        number = oc.order_number.to_s
        number.start_with?('#') ? number : "##{number}"
      end

      def search_products(query)
        results = Products.search(@shop, query)
        record('search_products', query: query.to_s.first(80), results: results.size)
        { 'ok' => true, 'products' => results }
      end

      def lookup_order(number, order_phone)
        digits = number.to_s.gsub(/\D/, '')
        return { 'ok' => false, 'error' => 'Ask the customer for their order number.' } if digits.blank? || digits.length > 15

        node = begin
          ShopifyOrders.find_by_number(@shop, digits)
        rescue ShopifyGraphql::Error => e
          Rails.logger.warn("[Whatsapp::Ai::Tools] Shopify order lookup failed shop=#{@shop.id}: #{e.message}")
          :unavailable
        end
        return { 'ok' => false, 'error' => 'Order lookup is unavailable right now. Hand off to the team.' } if node == :unavailable

        record('lookup_order', order_number: "##{digits}", found: node.present?)
        return { 'ok' => false, 'error' => "No order ##{digits} found. Ask the customer to check the number." } if node.blank?

        oc = local_order(node['id'])
        owners = (ShopifyOrders.phones(node) + [Whatsapp::Inbox::OrderLookup.last10(oc&.customer_number)])
                 .select { |p| p.length >= 10 }.uniq
        if owners.empty?
          return { 'ok' => false, 'error' => "Order ##{digits} exists but its owner can't be verified here. Hand off to the team." }
        end

        given = Whatsapp::Inbox::OrderLookup.last10(order_phone)
        mine = @conversation.phone_last10.to_s
        verified = owners.include?(mine) || (given.length >= 10 && owners.include?(given))
        unless verified
          return { 'ok' => false, 'needs_verification' => true,
                   'error' => 'Ask the customer for the phone number used on this order, then call lookup_order again with it. Never reveal order details before that.' }
        end

        order = ShopifyOrders.present(node, Whatsapp::ShopTimezone.for(@shop))
        if oc
          @context['_orders'] = (orders + [oc]).uniq(&:id)
          order['awaiting_cod_confirmation'] = oc.is_cod_order == true && ContextBuilder::AWAITING.include?(oc.status.to_s)
          order['cod_verification_status'] = Whatsapp::Inbox::OrderLookup.status_label(oc).presence
          order['order_status_url'] ||= oc.order_status_url.presence
        end
        { 'ok' => true, 'order' => order.compact }
      end

      def local_order(gid)
        numeric = gid.to_s[/\d+\z/]
        return nil if numeric.blank?

        OrderConfirmation.where(shop_id: @shop.id, order_id: [numeric, gid.to_s]).order(created_at: :desc).first
      end

      def confirm_order(number)
        load_own_order(number)
        oc = find_order(number, awaiting_orders)
        unless oc
          other = find_order(number, orders)
          return { 'ok' => false, 'error' => "Order #{label(other)} is not awaiting confirmation (#{Whatsapp::Inbox::OrderLookup.status_label(other)}). Tell the customer." } if other

          return { 'ok' => false, 'error' => 'No pending COD order with that number. Ask for the order number or call lookup_order.' }
        end

        unless @dry_run
          oc.reload
          if Whatsapp::CodVerificationActions.terminal?(oc)
            return { 'ok' => false, 'error' => "Order is already #{oc.status}." }
          end

          Whatsapp::CodVerificationActions.confirm!(shop: @shop, oc: oc)
        end
        record('confirm_cod_order', order_number: label(oc), ok: true)
        { 'ok' => true, 'order_number' => label(oc), 'status' => 'confirmed' }
      end

      CANCELLED = %w[COD-Cancelled COD-Auto-Cancelled COD-AUTO-CANCELLED].freeze
      CANCEL_FAILURES = {
        'already_paid' => 'This order is already paid online, so it cannot be cancelled here. Hand off to the team for a refund.',
        'already_fulfilled' => 'This order has already been shipped, so it cannot be cancelled now. Explain this and offer the return process from STORE KNOWLEDGE.',
        'already_cancelled' => 'This order is already cancelled. Tell the customer.',
        'not_found' => 'The order could not be found in the store. Hand off to the team.'
      }.freeze

      def cancellable_orders
        orders.select { |oc| oc.is_cod_order == true && !CANCELLED.include?(oc.status.to_s) }
      end

      def cancel_order(number)
        return { 'ok' => false, 'error' => 'Cancelling is not allowed. Hand off.' } unless @setting.allow_cancel

        @cancel_attempted = true
        load_own_order(number)
        oc = find_order(number, cancellable_orders)
        unless oc
          other = find_order(number, orders)
          return { 'ok' => false, 'error' => "Order #{label(other)} is already cancelled or not a COD order. Tell the customer." } if other

          return { 'ok' => false, 'error' => 'That order is not in CONTEXT.orders. Call lookup_order with the number first, then try again.' }
        end

        if @dry_run
          record('cancel_cod_order', order_number: label(oc), ok: true)
          return { 'ok' => true, 'order_number' => label(oc), 'status' => 'cancelled' }
        end

        oc.reload
        return { 'ok' => false, 'error' => CANCEL_FAILURES['already_cancelled'] } if CANCELLED.include?(oc.status.to_s)

        result = Whatsapp::CodVerificationActions.cancel!(shop: @shop, oc: oc, only_if_cancelled: true)
        code = result.respond_to?(:code) ? result.code.to_s : nil
        record('cancel_cod_order', order_number: label(oc), ok: result.cancelled ? true : false, code: code)
        if result.cancelled
          { 'ok' => true, 'order_number' => label(oc), 'status' => 'cancelled' }
        else
          { 'ok' => false, 'error' => CANCEL_FAILURES[code] || 'The order could not be cancelled automatically. Hand off to the team.' }
        end
      end

      def payment_link(number)
        shop_note = @context['payment_link_note']
        return { 'ok' => false, 'error' => "#{shop_note} Explain this to the customer; do not hand off." } if shop_note.present?

        load_own_order(number)
        oc = find_order(number, paylink_orders)
        unless oc
          other = find_order(number, orders)
          note = other && ContextBuilder.new(@conversation).order_json(other)['payment_link_note']
          return { 'ok' => false, 'error' => "#{note || 'No COD order with that number is waiting for payment.'} Explain this to the customer; do not hand off." }
        end

        if @dry_run
          record('send_payment_link', order_number: label(oc), ok: true)
          return { 'ok' => true, 'sent' => true }
        end

        result = Whatsapp::Inbox::PaymentLinkSender.call(conversation: @conversation, order_confirmation: oc, agent: nil)
        record('send_payment_link', order_number: label(oc), ok: result == :sent, result: result.to_s)
        return { 'ok' => true, 'sent' => true } if result == :sent
        return { 'ok' => true, 'sent' => true, 'note' => 'A payment link was already sent a few minutes ago.' } if result == :rate_limited

        { 'ok' => false, 'error' => 'The payment link could not be sent. Hand off to the team.' }
      end

      def place_order(args)
        result = OrderPlacer.call(conversation: @conversation, args: args, dry_run: @dry_run)
        return result if result['needs_confirmation']

        record('place_cod_order', ok: result['ok'], order_number: result.dig('order', 'order_number'),
                                  product: result.dig('order', 'product'), quantity: result.dig('order', 'quantity'))
        result
      end

      def discount_code
        result = DiscountGranter.call(conversation: @conversation, setting: @setting, cart: @context['cart'], dry_run: @dry_run)
        record('get_discount_code', ok: result['ok'], code: result['code'], reused: result['reused'])
        result
      end

      def function(name, description, properties = {}, required = properties.keys)
        {
          type: 'function',
          function: {
            name: name,
            description: description,
            strict: true,
            parameters: { type: 'object', properties: properties, required: required, additionalProperties: false }
          }
        }
      end

      def reply_def
        function('reply', 'Send the final message to the customer and finish.', {
                   text: { type: 'string', description: 'The WhatsApp message to send.' },
                   intent: { type: 'string', enum: INTENTS }
                 })
      end

      def handoff_def
        function('handoff', 'Pass the conversation to the human team and finish.', {
                   reason: { type: 'string', enum: HANDOFF_REASONS },
                   customer_message: { type: 'string', description: 'Short message telling the customer the team will help. Same language as the customer.' },
                   note: { type: 'string', description: 'One-line summary for the team, including order number and any details collected.' }
                 })
      end

      def lookup_order_def
        function('lookup_order', 'Look up an order in Shopify by its number: status, payment, shipping and tracking.', {
                   order_number: { type: 'string', description: 'Order number the customer gave, e.g. 1745.' },
                   order_phone: { type: 'string', description: 'Phone number used on the order if the customer gave one, else empty string.' }
                 })
      end

      def search_products_def
        function('search_products', 'Search the store catalog for products by name, type or keyword.', {
                   query: { type: 'string', description: 'Search words, e.g. "cotton kurta" or "black sneakers".' }
                 })
      end

      def order_def(name, description)
        function(name, description, { order_number: { type: 'string', description: 'Order number, e.g. #1234.' } })
      end

      def place_order_def
        function('place_cod_order', 'Price or create a cash-on-delivery order. First call with confirmed=false to get the exact total (COD fee, shipping, discount, tax) to show the customer; call with confirmed=true only after they say yes to that summary.', {
                   variant_id: { type: 'string', description: 'variant_id from search_products or cart product_details.' },
                   quantity: { type: 'integer', description: 'Number of units, 1-5.' },
                   full_name: { type: 'string' },
                   address1: { type: 'string', description: 'House/flat, building, street.' },
                   address2: { type: 'string', description: 'Area / landmark, or empty string.' },
                   city: { type: 'string' },
                   state: { type: 'string' },
                   pincode: { type: 'string' },
                   apply_discount: { type: 'boolean', description: 'True if the customer received a discount code in this chat and wants it applied.' },
                   confirmed: { type: 'boolean', description: 'false = only price it; true = create the order (customer already said yes to the summary).' }
                 })
      end

      def discount_def
        function('get_discount_code', 'Get the one discount code the store allows for this customer. Returns the code, its value and a link that applies it.')
      end
    end
  end
end
