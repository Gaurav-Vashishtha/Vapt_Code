module Admin
  # Support team: per-shop WhatsApp charge multipliers, entered by shop ID.
  class ShopChargeOverridesController < Admin::ApplicationController
    # Index search box: type a shop ID (Administrate searches shop_id).
    def scoped_resource
      resource_class.includes(:shop)
    end

    # Blank multipliers mean "no override" (nil), not 0 (= free).
    def resource_params
      params.require(resource_class.model_name.param_key)
            .permit(dashboard.permitted_attributes(action_name))
            .transform_values { |value| value.is_a?(String) && value.strip.empty? ? nil : value }
    end

    # /admin/shop_charge_overrides/new?shop_id=123 opens the form for that shop, or its
    # existing override when it already has one.
    def new
      if params[:shop_id].present? && (existing = resource_class.find_by(shop_id: params[:shop_id]))
        redirect_to [namespace, existing], notice: "Shop #{existing.shop_id} already has an override — edit it here."
        return
      end
      resource = new_resource
      resource.shop_id = params[:shop_id] if params[:shop_id].present?
      authorize_resource(resource)
      render locals: { page: Administrate::Page::Form.new(dashboard, resource) }
    end
  end
end
