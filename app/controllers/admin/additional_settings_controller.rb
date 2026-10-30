module Admin
  class AdditionalSettingsController < Admin::ApplicationController
    def scoped_resource
      resource_class.includes(:shop)
    end

    # Invalid JSON is passed through as text so the model validation reports it on the form.
    def resource_params
      permitted = params.require(resource_class.model_name.param_key)
                        .permit(dashboard.permitted_attributes(action_name)).to_h
      raw = permitted["third_party_payment_method_rules"]
      if raw.is_a?(String)
        text = raw.strip
        permitted["third_party_payment_method_rules"] =
          if text.empty?
            {}
          else
            begin
              JSON.parse(text)
            rescue JSON::ParserError
              text
            end
          end
      end
      permitted
    end

    def new
      if params[:shop_id].present? && (existing = resource_class.find_by(shop_id: params[:shop_id]))
        redirect_to [namespace, existing], notice: "Shop #{existing.shop_id} already has additional settings — edit them here."
        return
      end
      resource = new_resource
      resource.shop_id = params[:shop_id] if params[:shop_id].present?
      authorize_resource(resource)
      render locals: { page: Administrate::Page::Form.new(dashboard, resource) }
    end

    def create
      super
      shop_id = params.dig(resource_class.model_name.param_key, :shop_id)
      record = resource_class.find_by(shop_id: shop_id) if shop_id.present?
      refresh_shop_payment_function(record.shop) if record && record.third_party_payment_method_rules.present?
    end

    def update
      super
      refresh_payment_function(requested_resource)
    end

    def destroy
      shop = requested_resource.shop
      super
      refresh_shop_payment_function(shop)
    end

    private

    # The checkout payment function reads these rules from its own metafield, not the database.
    def refresh_payment_function(record)
      return unless record&.persisted? && record.previous_changes.key?("third_party_payment_method_rules")

      refresh_shop_payment_function(record.shop)
    end

    def refresh_shop_payment_function(shop)
      return if shop.blank?

      ShopifyServices::PaymentCustomizationService.call(shop, "")
    rescue StandardError => e
      Rails.logger.error("[Admin::AdditionalSettings] payment function refresh failed shop_id=#{shop&.id} #{e.class}: #{e.message}")
    end
  end
end
