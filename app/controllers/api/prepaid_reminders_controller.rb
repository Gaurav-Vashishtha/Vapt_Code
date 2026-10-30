module Api
  # Reads and replaces the per-shop prepaid reminder list. Stored as a JSON
  # array on `settings.prepaid_reminders` — see Setting#matching_prepaid_reminders
  # for how the scheduler matches by cart total.
  class PrepaidRemindersController < AuthenticatedController
    SUPPORTED_LANGUAGES = %w[en hi es fr ar].freeze
    DISCOUNT_TYPES      = %w[FIXED PERCENTAGE].freeze

    def show
      render json: { reminders: reminders_array }
    end

    # Replaces the entire array atomically. Simpler than per-row CRUD given
    # the array is small and the UI submits the full edited state anyway.
    def update
      raw = params[:reminders]
      return render(json: { error: 'reminders must be an array' }, status: :bad_request) unless raw.is_a?(Array)

      validated = raw.map.with_index { |r, i| normalize_and_validate!(r, i) }
      sorted = validated.sort_by { |r| [r['cart_min'].to_f || -Float::INFINITY, r['delay_minutes'].to_i] }

      @shop.setting.update!(prepaid_reminders: sorted)
      render json: { reminders: reminders_array }
    rescue ArgumentError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    # The prepaid_reminders jsonb cell is expected to hold an array, but legacy
    # rows can contain a double-encoded JSON string (e.g. the literal "[]"),
    # which would serialize as {"reminders":"[]"} and hang the settings UI on
    # "Loading reminders…". Always hand the client a real array.
    def reminders_array
      raw = @shop.setting.reload.prepaid_reminders
      return raw if raw.is_a?(Array)

      if raw.is_a?(String)
        parsed = begin
          JSON.parse(raw)
        rescue JSON::ParserError
          nil
        end
        return parsed if parsed.is_a?(Array)
      end

      []
    end

    def normalize_and_validate!(raw, index)
      r = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
      label = "reminder ##{index + 1}#{r['label'].present? ? " (#{r['label']})" : ''}"

      delay = r['delay_minutes'].to_i
      raise ArgumentError, "#{label}: delay_minutes must be a positive number" unless delay > 0

      cart_min = r['cart_min'].present? ? r['cart_min'].to_f : nil
      cart_max = r['cart_max'].present? ? r['cart_max'].to_f : nil
      raise ArgumentError, "#{label}: cart_min must be ≥ 0" if cart_min && cart_min.negative?
      raise ArgumentError, "#{label}: cart_max must be > cart_min" if cart_min && cart_max && cart_max <= cart_min

      template_key = r['template_key'].presence
      if template_key && ::Whatsapp::PrepaidTemplateLibrary.find(template_key).nil?
        raise ArgumentError, "#{label}: unknown template_key '#{template_key}'"
      end

      language = r['language'].presence
      if language && !SUPPORTED_LANGUAGES.include?(language)
        raise ArgumentError, "#{label}: language '#{language}' is not supported"
      end

      discount_type = r['discount_type'].presence
      if discount_type && !DISCOUNT_TYPES.include?(discount_type)
        raise ArgumentError, "#{label}: discount_type must be one of #{DISCOUNT_TYPES.join(', ')}"
      end

      bsp_template_id = r['bsp_template_id'].presence
      if bsp_template_id && !@shop.whatsapp_templates.exists?(id: bsp_template_id)
        raise ArgumentError, "#{label}: unknown BSP WhatsApp template"
      end

      {
        'id'            => r['id'].presence || SecureRandom.uuid,
        'enabled'       => r['enabled'] != false,
        'label'         => r['label'].presence,
        'delay_minutes' => delay,
        'cart_min'      => cart_min,
        'cart_max'      => cart_max,
        'discount'      => r['discount'].present? ? r['discount'].to_f : nil,
        'discount_type' => discount_type,
        # When true, the order's Shopify shipping charge is rolled into the
        # prepaid discount (e.g. ₹100 discount + ₹50 shipping → ₹150 off).
        'add_shipping'  => r['add_shipping'] == true,
        'template_key'  => template_key,
        # Per-reminder override for the merchant's own BSP WhatsApp template.
        # When set (and the BSP account is ready), the send goes over BSP.
        'bsp_template_id' => bsp_template_id ? bsp_template_id.to_i : nil,
        'language'      => language
      }
    end
  end
end
