class PartialRuleSetsController < AuthenticatedController
  before_action :set_shop, only: %i[create index update find_partial_rule_set destroy show reorder]
  
    # Create a new partial rule set
    def create
      # Accept product_ids as comma-separated string or array
      raw = partial_rule_set_params["product_ids"]
      product_ids = raw.is_a?(Array) ? raw.map(&:to_s).map(&:strip) : raw.to_s.split(",").map(&:strip)
      product_ids = product_ids.reject(&:blank?)

      attrs = with_cleared_json_params(partial_rule_set_params.except("product_ids").to_h)
      product_scope = attrs["product_scope"].presence || (product_ids.any? ? "include" : "all")
      attrs["product_scope"] = product_scope
      attrs["is_all"] = (product_scope == "all") # backward compatibility

      collection_ids = Array(attrs["collection_ids"]).map(&:to_s).map(&:strip).reject(&:blank?)
      attrs["collection_ids"] = collection_ids
      attrs["collection_scope"] = attrs["collection_scope"].presence || (collection_ids.any? ? "include" : "all")

      partial_rule_set = @shop.partial_rule_sets.new(attrs)
      partial_rule_set.product_ids = product_ids

      # Attempt to save the partial rule set
      if partial_rule_set.save
        update_setting_flags_from_params
        sync_rule_sets_metafield
        render json: partial_rule_set, status: :created
      else
        render json: { errors: partial_rule_set.errors.full_messages }, status: :unprocessable_entity
      end
    end
  
    # Show an individual partial rule set
    def show
      @partial_rule_set = @shop.partial_rule_sets.find(params[:id])
      render json: @partial_rule_set
    end
  
    # List all partial rule sets
    def index
      partial_rule_sets = @shop.partial_rule_sets.all
      render json: partial_rule_sets
    end
  
    # Update an existing partial rule set
    def update
      @partial_rule_set = @shop.partial_rule_sets.find(params[:id])
      raw = partial_rule_set_params[:product_ids]
      product_ids = raw.is_a?(Array) ? raw.map(&:to_s).map(&:strip) : raw.to_s.split(",").map(&:strip)
      product_ids = product_ids.reject(&:blank?)

      attributes = with_cleared_json_params(partial_rule_set_params.to_h.except("product_ids"))
      attributes["product_ids"] = product_ids
      product_scope = attributes["product_scope"].presence || (product_ids.any? ? "include" : "all")
      attributes["product_scope"] = product_scope
      attributes["is_all"] = (product_scope == "all") # backward compatibility

      collection_ids = Array(attributes["collection_ids"]).map(&:to_s).map(&:strip).reject(&:blank?)
      attributes["collection_ids"] = collection_ids
      attributes["collection_scope"] = attributes["collection_scope"].presence || (collection_ids.any? ? "include" : "all")

      if @partial_rule_set.update(attributes)
        update_setting_flags_from_params
        sync_rule_sets_metafield
        render json: @partial_rule_set
      else
        render json: { errors: @partial_rule_set.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # Delete a partial rule set
    def destroy
      @partial_rule_set = @shop.partial_rule_sets.find(params[:id])
      @partial_rule_set.destroy
      sync_rule_sets_metafield
      head :no_content
    end

    # Reorder partial rule sets by position
    def reorder
      rule_ids = params[:rule_ids]&.map(&:to_i) || []
      return render json: { errors: ["rule_ids is required"] }, status: :unprocessable_entity if rule_ids.empty?

      PartialRuleSet.transaction do
        rule_ids.each_with_index do |rule_id, index|
          rule = @shop.partial_rule_sets.unscoped.find_by(id: rule_id)
          rule&.update_column(:position, index)
        end
      end

      sync_rule_sets_metafield
      partial_rule_sets = @shop.partial_rule_sets.reload
      render json: partial_rule_sets
    end

    private

    def sync_rule_sets_metafield
      @shop.sync_partial_rule_sets_metafields
    rescue => e
      Rails.logger.warn "[PartialRuleSetsController] sync_partial_rule_sets_metafields failed: #{e.message}"
    end

    # Shop-level flags the COD form / partial rule set form submits alongside the
    # rule payload.
    SETTING_FLAGS_FROM_RULE_FORM = %i[
      cod_form_enabled
      include_shipping_in_payment_options
    ].freeze

    # Persist those flags to settings when present in params.
    # Do not use .presence — false is valid and must be persisted when the user unchecks the box.
    def update_setting_flags_from_params
      setting = @shop.setting
      return unless setting

      changes = SETTING_FLAGS_FROM_RULE_FORM.each_with_object({}) do |flag, acc|
        value = params[flag]
        value = params.dig(:partial_rule_set, flag) if value.nil?
        next if value.nil?

        bool = ActiveModel::Type::Boolean.new.cast(value)
        acc[flag] = bool unless setting.public_send(flag) == bool
      end
      return if changes.empty?

      # Use regular update so Setting callbacks run and Shopify metafields are refreshed.
      unless setting.update(changes)
        Rails.logger.warn "[PartialRuleSetsController] Failed to update #{changes.keys.join(', ')} for setting_id=#{setting.id}: #{setting.errors.full_messages.join(', ')}"
      end
    end

    def partial_rule_set_params
      params.require(:partial_rule_set).permit(
        :id, :rule_name, :amount, :amount_type, :product_ids, :is_all, :product_scope,
        :is_enabled, :is_cart_rule, :discount_code, :discount_value, :discount_type,
        :amount_to_show, :sub_heading, :min_cart_range, :max_cart_range, :description_template,
        :custom_save_text,
        :shipping_charge, :shipping_charge_text,
        :zipcode_blacklist_enabled, :zipcode_blacklist,
        :zipcode_whitelist_enabled, :zipcode_whitelist,
        :variant_scope, :collection_scope,
        :match_any_product, :checkout_cod_only, :free_delivery,
        variant_ids: [], collection_ids: [], phone_blacklist: [], email_blacklist: [],
        rto_engine: [:enabled, :hide_at_band, :min_score],
        cart_items_range: [:min_cart_items, :max_cart_items],
        repeat_customer_discount: [:enabled, :discount_type, :discount_value],
        cod_cooling_period: [:enabled, :days]
      )
    end

    # JSON columns the form clears by sending null. permit drops a key whose
    # value is null, which would turn "switch it off" into a silent no-op.
    CLEARABLE_JSON_PARAMS = %w[rto_engine cart_items_range repeat_customer_discount cod_cooling_period].freeze

    def with_cleared_json_params(attrs)
      raw = params[:partial_rule_set]
      return attrs unless raw.respond_to?(:key?)

      CLEARABLE_JSON_PARAMS.each do |key|
        attrs[key] = nil if raw.key?(key) && raw[key].nil?
      end
      attrs
    end
  end