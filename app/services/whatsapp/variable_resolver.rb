module Whatsapp
  # Given a template's variable_mapping ({ "1" => "customer.first", ... })
  # and a webhook payload, return Meta-formatted body parameters in positional order.
  #
  # The mapping says which event-variable feeds each {{N}} slot.
  # The EventRegistry's `path` says where that variable lives in the payload.
  class VariableResolver < ApplicationService
    def initialize(template:, payload:)
      @template = template
      @payload = payload.respond_to?(:to_h) ? payload.to_h.deep_stringify_keys : (payload || {})
    end

    BLANK_FALLBACK = '—'.freeze

    def call
      # Drive the parameter list off the BODY's actual {{N}} placeholders, not
      # the saved mapping. Meta counts the placeholders in the approved template
      # and rejects the send with 132000 if we supply a different number — which
      # happens whenever the mapping is empty or only partially filled. We emit
      # exactly one param per placeholder, in order, filling unmapped slots with
      # the blank fallback so the count always matches.
      positions = body_placeholder_positions
      return [] if positions.empty?

      mapping = template.variable_mapping || {}
      var_index = EventRegistry.variables_for(template.event_type_key).index_by { |v| v[:key] }

      positions.map do |position|
        var_key = mapping[position.to_s] || mapping[position]
        var_def = var_key ? var_index[var_key] : nil

        value =
          if var_def.nil?
            ''
          elsif var_def[:source] == :literal
            # Literal variables (campaign.code etc) aren't in the payload — caller passes them in.
            payload.dig('literals', var_key) || ''
          else
            dig_path(payload, var_def[:path])
          end

        # Shopify order webhooks carry no `line_items_count` (only our own
        # abandoned-cart / Shopflo payloads set it), so `*.items_count` came out
        # blank on every real order. Derive it from the sibling line_items.
        if value.to_s.empty? && var_def && var_def[:path].to_s.end_with?('.line_items_count')
          value = derived_items_count(var_def[:path])
        end

        # Variables with format: :postal_address resolve to a hash (Shopify
        # address shape) and need to be flattened to a single string. Meta
        # disallows newlines inside body parameters, so the formatter uses
        # comma separators.
        if var_def && var_def[:format] == :postal_address && value.is_a?(Hash)
          value = format_postal_address(value)
        elsif var_def && var_def[:format] == :line_items_summary
          value = format_line_items_summary(value)
        end

        text = value.to_s
        if text.empty?
          Rails.logger.warn("[whatsapp/variables] template=#{template.id} position=#{position} var=#{var_key.inspect} resolved to blank — substituting '#{BLANK_FALLBACK}'")
          text = BLANK_FALLBACK
        end

        { 'type' => 'text', 'text' => text }
      end
    end

    # Distinct {{N}} positions in the BODY component, in numeric order. This is
    # what Meta expects body parameters for.
    def body_placeholder_positions
      body = Array(template.components).find do |c|
        c.is_a?(Hash) && c['type'].to_s.casecmp?('BODY')
      end
      text = body && (body['text'] || body[:text]).to_s
      return [] if text.to_s.empty?
      text.scan(/\{\{(\d+)\}\}/).flatten.map(&:to_i).uniq.sort
    end

    private

    attr_reader :template, :payload

    # Flatten a Shopify-shaped address hash into a single comma-separated line
    # suitable for a Meta template body parameter. Newlines are disallowed by
    # Meta inside body parameters (132000), so we collapse to a comma list.
    # Empty / nil components are dropped silently.
    def format_postal_address(addr)
      parts = [
        addr['address1'] || addr[:address1],
        addr['address2'] || addr[:address2],
        addr['city']     || addr[:city],
        addr['zip']      || addr[:zip],
        addr['province'] || addr[:province],
        addr['country_code'] || addr[:country_code] || addr['country'] || addr[:country]
      ]
      parts.map { |p| p.to_s.strip }.reject(&:empty?).join(', ')
    end

    # Separator between products in an order.products value. Comma-joined (not
    # newline) because Meta rejects newlines inside body parameters (132000).
    LINE_ITEM_SEPARATOR = ', '.freeze

    # Render an order's line items as "<product - variant> : Qty <quantity>"
    # entries, one per line. Accepts the raw Shopify `line_items` array (real
    # send) or a pre-formatted string (the registry sample used for previews),
    # which is passed through untouched. Items without a title are skipped.
    #
    # Shopify's `title` is the PRODUCT title only; the variant lives in
    # `variant_title` (and `name` is the "Title - Variant" combination). Using
    # `title` alone made every size/colour read as the same item.
    def format_line_items_summary(value)
      return value.to_s unless value.is_a?(Array)

      value.map do |li|
        next nil unless li.is_a?(Hash)
        title = line_item_display_name(li)
        next nil if title.empty?
        qty = (li['quantity'] || li[:quantity]).to_s.strip
        qty.empty? ? title : "#{title} : Qty #{qty}"
      end.compact.join(LINE_ITEM_SEPARATOR)
    end

    DEFAULT_VARIANT_TITLE = 'Default Title'.freeze

    def line_item_display_name(li)
      title = (li['title'] || li[:title]).to_s.strip
      variant = (li['variant_title'] || li[:variant_title]).to_s.strip
      name = (li['name'] || li[:name]).to_s.strip

      variant = '' if variant.casecmp?(DEFAULT_VARIANT_TITLE)
      return "#{title} - #{variant}" if title.present? && variant.present?
      return name if name.present?

      title
    end

    # Total quantity across the line items next to a `*.line_items_count`
    # path (e.g. order.line_items_count → order.line_items). Blank when the
    # payload has no line items, so the caller's fallback still applies.
    def derived_items_count(count_path)
      items = dig_path(payload, count_path.to_s.sub(/line_items_count\z/, 'line_items'))
      return '' unless items.is_a?(Array) && items.any?

      items.sum { |li| li.is_a?(Hash) ? [(li['quantity'] || li[:quantity]).to_i, 1].max : 1 }.to_s
    end

    # Resolve dot-separated path. Supports nested hashes and the `.first` suffix for arrays.
    # e.g. 'order.customer.first_name', 'customer.tags.first'
    def dig_path(hash, path)
      return '' if path.blank?
      path.to_s.split('.').reduce(hash) do |acc, key|
        break '' if acc.nil?
        if key == 'first' && acc.is_a?(Array)
          acc.first
        elsif acc.respond_to?(:[])
          acc[key] || acc[key.to_sym]
        else
          break ''
        end
      end
    end
  end
end
