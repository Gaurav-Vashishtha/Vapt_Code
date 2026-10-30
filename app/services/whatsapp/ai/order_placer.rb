# frozen_string_literal: true

module Whatsapp
  module Ai
    # Prices and creates a cash-on-delivery order for the customer chatting on WhatsApp.
    # Shops with the COD Form live get the form's own server-side quote (COD fee, shipping rates,
    # offers, COD eligibility rules, tax, discount code) and draft builder, so the order matches
    # what the form would have created. Other shops get the classic checkout path plus their
    # flat COD fee.
    class OrderPlacer
      MAX_QUANTITY = 5
      COOLDOWN = 10.minutes
      SOURCE = 'api'

      VARIANT_QUERY = <<~GRAPHQL
        query($id: ID!) {
          node(id: $id) {
            ... on ProductVariant { id title price availableForSale product { title status } }
          }
        }
      GRAPHQL

      def self.call(conversation:, args:, dry_run: false)
        new(conversation, args, dry_run).call
      end

      def initialize(conversation, args, dry_run)
        @conversation = conversation
        @shop = conversation.shop
        @args = args.is_a?(Hash) ? args : {}
        @dry_run = dry_run
        @confirmed = @args['confirmed'] == true
      end

      def call
        problem = validate_input
        return error(problem) if problem

        variant = load_variant
        return error('That product option was not found. Call search_products and use a variant_id from it.') unless variant
        unless variant['availableForSale'] && variant.dig('product', 'status').to_s.upcase == 'ACTIVE'
          return error('That product option is out of stock. Offer another size or product.')
        end

        @variant = variant
        config = form_config
        config ? form_flow(config) : classic_flow
      rescue ShopifyGraphql::Error => e
        Rails.logger.warn("[Whatsapp::Ai::OrderPlacer] shop=#{@shop.id} #{e.message}")
        error('The store could not be reached. Hand off to the team with the order details in the note.')
      rescue CodForm::Errors::InvalidItem
        error('That product cannot be ordered this way. Share the product link instead.')
      end

      private

      def validate_input
        missing = %w[variant_id full_name address1 city state pincode].select { |k| @args[k].to_s.strip.blank? }
        return "Missing #{missing.join(', ')}. Ask the customer for it." if missing.any?
        return "Quantity must be between 1 and #{MAX_QUANTITY}." unless (1..MAX_QUANTITY).cover?(quantity)
        return 'The pincode must be 6 digits. Ask the customer to check it.' if india? && !pincode.match?(/\A[1-9]\d{5}\z/)

        nil
      end

      # ---- COD Form path ------------------------------------------------------------------------

      def form_config
        config = CodForm::ShopConfig.for(@shop)
        CodForm::Availability.usable?(CodForm::Availability.call(@shop, config: config)) ? config : nil
      rescue StandardError => e
        Rails.logger.warn("[Whatsapp::Ai::OrderPlacer] COD form unavailable shop=#{@shop.id}: #{e.class}: #{e.message}")
        nil
      end

      def form_flow(config)
        items = [{ 'variant_id' => variant_numeric_id, 'quantity' => quantity }]
        lines = CodForm::CatalogService.lines(@shop, items, country: country)
        form = CodForm::Form.where(shop_id: @shop.id).active.ordered.first || CodForm::Form.default_for(@shop)
        session = CodForm::Session.new(
          shop_id: @shop.id, cod_form_id: form&.id, form_version: form&.published_version,
          status: CodForm::Session::STATUS_OPEN, source: SOURCE, is_test: false, country_code: country,
          currency: lines.first && lines.first['currency'], locale: 'en', public_id: "wa_ai_#{SecureRandom.hex(8)}",
          cart_snapshot: { 'items' => items, 'source' => SOURCE }, address: { 'country' => country },
          attribution: {}, tracking: {}, ab_assignments: {}
        )
        params = {
          'items' => items,
          'address' => form_address,
          'contact' => { 'first_name' => first_name, 'last_name' => last_name, 'phone' => phone_e164 },
          'discount_code' => discount_code_to_apply
        }.compact
        built = CodForm::QuoteService.build(
          shop: @shop, config: config, session: session, params: params,
          stage: @confirmed ? 'submit' : 'quote', persist: false, force_tax: @confirmed
        )
        quote = built.quote
        blocker = form_blocker(quote)
        return error(blocker) if blocker

        summary = form_summary(quote, built.currency)
        return { 'ok' => true, 'needs_confirmation' => true, 'summary' => summary } unless @confirmed
        return { 'ok' => true, 'dry_run' => true, 'order' => summary.merge('order_number' => '#TEST') } if @dry_run
        return duplicate_error unless take_cooldown

        contact = {
          'first_name' => first_name, 'last_name' => last_name, 'email' => '',
          'phone_e164' => built.phone['valid'] == true ? built.phone['e164'].to_s : phone_e164,
          'phone_national' => built.phone['valid'] == true ? built.phone['national'].to_s : ''
        }
        draft_input = CodForm::Engine::DraftOrderBuilder.build(
          quote: quote, contact: contact, address: CodForm::OrderService.draft_address(built.address),
          meta: {
            'shop_tags' => ['WhatsApp-AI-Order'], 'verified' => true,
            'verification_tag' => @shop.setting&.verification_tag.presence || '✅ COD-Verified',
            'session_id' => session.public_id, 'form_id' => form&.id, 'is_test' => false,
            'attribution' => {}, 'custom_fields' => [], 'customer_gid' => nil,
            'note_fields' => { 'gst_number' => '', 'note' => 'Order placed by the WhatsApp AI assistant' },
            'otp_phone_e164' => contact['phone_e164'], 'country' => country
          }
        )
        created = ShopifyServices::CodOrderCreateService.call(
          @shop, {}, {}, {}, nil, nil, true,
          form_context: { draft_input: draft_input,
                          expected_total_cents: quote['total_cents'],
                          tolerance_cents: [2, Array(draft_input['lineItems']).size].max }
        )
        created_result(created, summary)
      end

      def form_blocker(quote)
        eligibility = quote['eligibility'] || {}
        unless eligibility['cod_allowed'] == true
          reason = eligibility['message'].to_s.presence || 'Cash on delivery is not available for this order/pincode.'
          return "#{reason} Tell the customer and offer to pay online with the checkout link."
        end
        return 'No delivery is available to this pincode. Tell the customer.' if quote.dig('shipping', 'none_available') == true
        if Array(quote['lines']).any? { |l| l['available'] == false || (l['max_quantity'] && l['quantity'].to_i > l['max_quantity'].to_i) }
          return 'Not enough stock for that quantity. Offer a lower quantity or another option.'
        end

        nil
      end

      def form_summary(quote, currency)
        line = Array(quote['lines']).first || {}
        code = quote['discount_code'].is_a?(Hash) ? quote['discount_code'] : {}
        {
          'product' => product_label,
          'quantity' => quantity,
          'currency' => currency,
          'items_total' => money(quote['subtotal_cents'] || line['line_subtotal_cents']),
          'discount' => quote['discount_total_cents'].to_i.positive? ? money(quote['discount_total_cents']) : nil,
          'discount_code' => code['status'] == 'applied' ? code['code'] : nil,
          'shipping' => quote['shipping_cents'].to_i.positive? ? money(quote['shipping_cents']) : 'Free',
          'cod_fee' => quote.dig('cod_fee', 'amount_cents').to_i.positive? ? money(quote.dig('cod_fee', 'amount_cents')) : nil,
          'tax' => tax_cents(quote).positive? ? money(tax_cents(quote)) : nil,
          'total' => money(quote['total_cents']),
          'payment' => 'Cash on delivery',
          'deliver_to' => delivery_line
        }.compact
      end

      def tax_cents(quote)
        tax = quote['tax'].is_a?(Hash) ? quote['tax'] : {}
        tax['status'] == 'calculated' && tax['required'] ? tax['amount_cents'].to_i : 0
      end

      def form_address
        {
          'country' => country, 'province' => province_code, 'city' => @args['city'].to_s.squish,
          'zip' => pincode, 'address1' => @args['address1'].to_s.squish, 'address2' => @args['address2'].to_s.squish
        }
      end

      def province_code
        raw = @args['state'].to_s.squish
        list = CodForm::CatalogService.provinces(country)
        match = list.find { |p| p['code'].to_s.casecmp?(raw) || p['name'].to_s.casecmp?(raw) } ||
                list.find { |p| p['name'].to_s.downcase.include?(raw.downcase) || raw.downcase.include?(p['name'].to_s.downcase) }
        match ? match['code'].to_s.sub(/\A#{country}-/i, '') : raw
      end

      # ---- classic checkout path ----------------------------------------------------------------

      def classic_flow
        unit = BigDecimal(@variant['price'].to_s)
        cod_fee = classic_cod_fee
        percent = discount_percent
        items_total = unit * quantity
        discount = percent ? (items_total * percent / 100).round(2) : 0
        total = items_total - discount + cod_fee
        summary = {
          'product' => product_label, 'quantity' => quantity, 'currency' => currency,
          'items_total' => format('%.2f', items_total),
          'discount' => discount.positive? ? format('%.2f', discount) : nil,
          'cod_fee' => cod_fee.positive? ? format('%.2f', cod_fee) : nil,
          'total' => format('%.2f', total), 'shipping' => 'as per store policy',
          'payment' => 'Cash on delivery', 'deliver_to' => delivery_line
        }.compact
        return { 'ok' => true, 'needs_confirmation' => true, 'summary' => summary } unless @confirmed
        return { 'ok' => true, 'dry_run' => true, 'order' => summary.merge('order_number' => '#TEST') } if @dry_run
        return duplicate_error unless take_cooldown

        created = ShopifyServices::CodOrderCreateService.call(
          @shop,
          { 'items' => [{ 'variant_id' => variant_numeric_id, 'quantity' => quantity }],
            'cart_level_discount_applications' => percent ? [{ 'value_type' => 'percentage', 'value' => percent.to_f, 'title' => discount_code_to_apply }] : [],
            'currency_code' => currency },
          classic_address, { phone: phone_e164, email: nil },
          cod_fee.positive? ? cod_fee.to_f : nil, nil, true
        )
        created_result(created, summary)
      end

      def classic_cod_fee
        setting = @shop.setting
        return BigDecimal('0') unless setting&.cod_fee_enabled

        BigDecimal(setting.cod_fees.to_s)
      rescue ArgumentError
        BigDecimal('0')
      end

      def classic_address
        {
          'first_name' => first_name, 'last_name' => last_name,
          'address1' => @args['address1'].to_s.squish, 'address2' => @args['address2'].to_s.squish,
          'city' => @args['city'].to_s.squish, 'province' => @args['state'].to_s.squish,
          'zip' => pincode, 'country' => country, 'phone' => phone_e164
        }
      end

      # ---- shared -------------------------------------------------------------------------------

      def created_result(created, summary)
        if created[:success]
          return { 'ok' => true, 'order' => summary.merge(
            'order_number' => created[:order_name].presence || "##{created[:order_number]}",
            'order_status_url' => created[:order_status_url]
          ).compact }
        end

        Rails.cache.delete(cooldown_key) unless created[:outcome_unknown]
        Rails.logger.warn("[Whatsapp::Ai::OrderPlacer] shop=#{@shop.id} create failed: #{created[:code]} #{created[:error]}")
        if created[:code] == 'total_changed'
          return error('The price changed while placing the order. Call place_cod_order again with confirmed=false and show the new total.')
        end

        error('The order could not be created. Share the product checkout link and hand off to the team with the details in the note.')
      end

      def load_variant
        raw = @args['variant_id'].to_s
        digits = raw[/\d+\z/]
        return nil if digits.blank?

        ShopifyGraphql.call(@shop, VARIANT_QUERY, { id: "gid://shopify/ProductVariant/#{digits}" })['node'].presence
      end

      def discount_code_to_apply
        code = @conversation.ai_discount.is_a?(Hash) ? @conversation.ai_discount : nil
        return nil unless code && @args['apply_discount'] == true && Time.zone.parse(code['expires_at'].to_s)&.future?

        code['code'].to_s.presence
      end

      def discount_percent
        return nil unless discount_code_to_apply

        value = @conversation.ai_discount['formatted'].to_s[/\d+(?:\.\d+)?/]
        value ? BigDecimal(value) : nil
      end

      def product_label
        [@variant.dig('product', 'title'), @variant['title']].reject { |t| t.blank? || t == 'Default Title' }.join(' - ')
      end

      def delivery_line
        [@args['full_name'], @args['address1'], @args['address2'], @args['city'], @args['state'], pincode]
          .map { |v| v.to_s.squish }.reject(&:blank?).join(', ')
      end

      def money(cents)
        return nil if cents.nil?

        format('%.2f', cents.to_i / 100.0)
      end

      def variant_numeric_id
        @variant['id'].to_s[/\d+\z/]
      end

      def quantity
        @quantity ||= @args['quantity'].to_i
      end

      def pincode
        @pincode ||= @args['pincode'].to_s.gsub(/\s/, '')
      end

      def first_name
        @args['full_name'].to_s.squish.split(' ', 2).first.to_s
      end

      def last_name
        @args['full_name'].to_s.squish.split(' ', 2)[1].to_s
      end

      def phone_e164
        "+#{@conversation.customer_wa_id.to_s.gsub(/\D/, '')}"
      end

      def country
        @shop.country_code.presence || 'IN'
      end

      def currency
        @shop.currency.presence || 'INR'
      end

      def india?
        country.to_s.upcase == 'IN'
      end

      def cooldown_key
        "wa_ai:order_placed:#{@conversation.id}"
      end

      def take_cooldown
        Rails.cache.write(cooldown_key, 1, expires_in: COOLDOWN, unless_exist: true)
      end

      def duplicate_error
        error('An order was already placed in this chat a few minutes ago. Do not place another one.')
      end

      def error(message)
        { 'ok' => false, 'error' => message }
      end
    end
  end
end
