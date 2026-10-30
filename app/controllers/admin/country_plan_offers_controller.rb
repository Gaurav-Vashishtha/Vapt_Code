module Admin
  # Support team: country-wise plan offers (price and/or free trial).
  class CountryPlanOffersController < Admin::ApplicationController
    # Blank number fields mean "not set" (nil), not 0.
    def resource_params
      params.require(resource_class.model_name.param_key)
            .permit(dashboard.permitted_attributes(action_name))
            .transform_values { |value| value.is_a?(String) && value.strip.empty? ? nil : value }
    end
  end
end
