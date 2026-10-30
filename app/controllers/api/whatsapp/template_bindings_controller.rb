module Api
  module Whatsapp
    class TemplateBindingsController < AuthenticatedController
      def index
        bindings = @shop.whatsapp_template_bindings.includes(:whatsapp_template).map { |b| serialize(b) }
        render json: { bindings: bindings }
      end

      # Lightweight flag for the plan-downgrade gate: is a WhatsApp account bound
      # with at least one notification turned on? Mirrors the backend block in
      # PlansController so the UI can warn before the merchant attempts a downgrade.
      def notifications_active
        # Allowlisted shops keep WhatsApp regardless of plan, so their
        # notifications never block a downgrade.
        active = @shop.whatsapp_notifications_active? && !@shop.whatsapp_bsp_plan_exempt?
        render json: { active: active }
      end

      def create
        event_type_key = params[:event_type_key].to_s
        template_id = params[:whatsapp_template_id]
        stage_index = params[:stage_index].present? ? params[:stage_index].to_i : 0
        offset_minutes = params[:offset_minutes].present? ? params[:offset_minutes].to_i : 0
        discount_config = sanitize_discount_config(params[:discount_config])

        return render(json: { error: 'event_type_key is required' }, status: :bad_request) if event_type_key.blank?
        return render(json: { error: 'whatsapp_template_id is required' }, status: :bad_request) if template_id.blank?
        return render(json: { error: 'unknown event' }, status: :unprocessable_entity) unless ::Whatsapp::EventRegistry.find(event_type_key)

        template = WhatsappTemplate
          .joins(:whatsapp_account)
          .where(whatsapp_accounts: { shop_id: @shop.id })
          .find_by(id: template_id)

        return render(json: { error: 'template not found' }, status: :not_found) unless template

        # Allow binding an existing approved template that isn't tied to this
        # event yet — "adopt" it into the event so the binding's event-match
        # validation passes. Only adopt templates that are unassigned and
        # category-compatible; never steal one already assigned to another event.
        if template.event_type_key.to_s != event_type_key
          if template.event_type_key.present?
            return render(json: { error: "template is already assigned to '#{template.event_type_key}'; change that automation first" }, status: :unprocessable_entity)
          end

          allowed = ::Whatsapp::EventRegistry.bindable_categories_for(event_type_key)
          if allowed.any? && !allowed.map(&:upcase).include?(template.category.to_s.upcase)
            return render(json: { error: "template category #{template.category} doesn't match this event (needs #{allowed.join(', ')})" }, status: :unprocessable_entity)
          end

          unless template.update(event_type_key: event_type_key)
            return render(json: { error: template.errors.full_messages.to_sentence }, status: :unprocessable_entity)
          end
        end

        if %w[cod_verification cod_verification_reminder].include?(event_type_key)
          button_error = ::Whatsapp::CodVerificationButtons.mapping_error(template.components)
          return render(json: { error: button_error }, status: :unprocessable_entity) if button_error
        end

        # If a discount is configured, the template must actually have a {{N}}
        # mapped to a discount.* variable — otherwise the code never reaches the
        # customer and (for auto mode) we'd leak a Shopify price rule per send.
        if discount_config && discount_config['mode'].to_s != 'none' && !template_maps_discount?(template)
          return render(
            json: { error: "This template has no discount placeholder. Map a {{N}} to 'Discount code' (or value/formatted) in Change personalization, or set Discount to None." },
            status: :unprocessable_entity
          )
        end

        # Upsert per (event, stage): the model's uniqueness scope is the same
        # tuple, so we look up by it and assign the rest of the fields.
        binding = @shop.whatsapp_template_bindings.find_or_initialize_by(
          event_type_key: event_type_key,
          stage_index: stage_index
        )
        binding.whatsapp_template = template
        binding.offset_minutes = offset_minutes
        if binding.new_record?
          binding.paused_at = @shop.whatsapp_template_bindings.for_event(event_type_key).paused.minimum(:paused_at)
        end
        binding.discount_config = discount_config if discount_config

        # Which number this event sends from. Defaults to the template's own
        # account (the template must exist in the sending number's WABA); a
        # different number under the same WABA can be chosen explicitly. The
        # model validates the WABA match.
        requested_account_id = params[:whatsapp_account_id]
        binding.whatsapp_account =
          if requested_account_id.present?
            @shop.whatsapp_accounts.find_by(id: requested_account_id)
          else
            template.whatsapp_account
          end

        if binding.save
          # An order_fulfilled automation depends on Shopify pushing
          # orders/fulfilled webhooks to our EventBridge target → SQS → SqsConsumerJob
          # → DispatchEventJob. Subscribe it here so merchants don't have to
          # toggle the legacy `fulfilment_whatsapp` setting just to wire up
          # the webhook. The service is idempotent — repeats are no-ops.
          if event_type_key == 'order_fulfilled'
            ShopifyServices::FulfilmentWebhookSubscribeService.call(@shop)
          end
          webhook_topic = ::Whatsapp::EventRegistry.webhook_topic(event_type_key)
          ShopifyServices::FulfilmentWebhookSubscribeService.call(@shop, webhook_topic) if webhook_topic
          render json: serialize(binding), status: :created
        else
          render json: { error: binding.errors.full_messages.to_sentence }, status: :unprocessable_entity
        end
      end

      def pause
        event_type_key = params[:event_type_key].to_s
        paused = ActiveModel::Type::Boolean.new.cast(params[:paused])
        return render(json: { error: 'event_type_key is required' }, status: :bad_request) if event_type_key.blank?
        if paused && !WhatsappTemplateBinding.pausable?(event_type_key)
          return render(json: { error: 'This notification cannot be paused' }, status: :unprocessable_entity)
        end

        bindings = WhatsappTemplateBinding.set_paused!(@shop, event_type_key, paused)
        return render(json: { error: 'not found' }, status: :not_found) if bindings.empty?

        render json: { bindings: bindings.sort_by(&:stage_index).map { |b| serialize(b) } }
      end

      def destroy
        binding = @shop.whatsapp_template_bindings.find_by(id: params[:id])
        return render(json: { error: 'not found' }, status: :not_found) unless binding

        binding.destroy!
        render json: { ok: true }
      end

      private

      # True when the template maps at least one {{N}} to a discount.* variable.
      def template_maps_discount?(template)
        (template.variable_mapping || {}).values.any? { |v| v.to_s.start_with?('discount.') }
      end

      def sanitize_discount_config(raw)
        return nil if raw.blank?
        cfg = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
        return nil unless cfg.is_a?(Hash)
        cfg = cfg.stringify_keys

        out = { 'mode' => cfg['mode'].to_s.presence || 'none' }
        return out if out['mode'] == 'none'

        # Default to percent when the UI left kind unset (it shows "Percent off"
        # as the default option without writing it to state until changed).
        out['kind']  = cfg['kind'].to_s.presence || 'percent'
        out['value'] = cfg['value'].to_f if cfg['value'].present?
        out['upto']  = cfg['upto'].to_f  if cfg['upto'].present?
        out['code']  = cfg['code'].to_s.upcase if cfg['code'].present?
        out['prefix'] = cfg['prefix'].to_s.upcase if cfg['prefix'].present?
        out['expiry_hours'] = cfg['expiry_hours'].to_i if cfg['expiry_hours'].present?
        out
      end

      def serialize(b)
        {
          id: b.id,
          event_type_key: b.event_type_key,
          whatsapp_template_id: b.whatsapp_template_id,
          template_name: b.whatsapp_template&.name,
          template_status: b.whatsapp_template&.status,
          template_language: b.whatsapp_template&.language,
          whatsapp_account_id: b.whatsapp_account_id,
          account_label: b.whatsapp_account&.display_label,
          account_phone: b.whatsapp_account&.display_phone_number,
          stage_index: b.stage_index,
          offset_minutes: b.offset_minutes,
          discount_config: b.discount_config,
          paused: b.paused?,
          paused_at: b.paused_at,
          pausable: WhatsappTemplateBinding.pausable?(b.event_type_key),
          created_at: b.created_at,
          updated_at: b.updated_at
        }
      end
    end
  end
end
