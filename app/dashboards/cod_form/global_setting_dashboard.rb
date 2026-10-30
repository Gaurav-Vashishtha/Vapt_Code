# frozen_string_literal: true

require "administrate/base_dashboard"

module CodForm
  class GlobalSettingDashboard < Administrate::BaseDashboard
    ATTRIBUTE_TYPES = {
      id: Field::Number,
      kill_switch: Field::Boolean,
      module_default_on: Field::Boolean,
      at_cap_behaviour: Field::Select.with_options(searchable: false,
                                                   collection: ::CodForm::GlobalSetting::AT_CAP_BEHAVIOURS),
      grace_orders: Field::Number,
      async_orders: Field::Boolean,
      usage_notice_thresholds: JsonTextField.with_options(rows: 2),
      settings: JsonTextField,
      created_at: Field::DateTime,
      updated_at: Field::DateTime
    }.freeze

    COLLECTION_ATTRIBUTES = %i[
      id
      kill_switch
      module_default_on
      at_cap_behaviour
      grace_orders
      async_orders
      updated_at
    ].freeze

    SHOW_PAGE_ATTRIBUTES = %i[
      id
      kill_switch
      module_default_on
      at_cap_behaviour
      grace_orders
      async_orders
      usage_notice_thresholds
      settings
      created_at
      updated_at
    ].freeze

    # usage_notice_thresholds: JSON array of percentages, e.g. [80, 100].
    # settings: JSON object, e.g. {"rate_limits": {"codf/session/ip": {"limit": 30, "period": 60}}}.
    FORM_ATTRIBUTES = %i[
      kill_switch
      module_default_on
      at_cap_behaviour
      grace_orders
      async_orders
      usage_notice_thresholds
      settings
    ].freeze

    COLLECTION_FILTERS = {}.freeze

    def display_resource(_global_setting)
      "COD Form global settings"
    end
  end
end
