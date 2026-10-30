# frozen_string_literal: true

require "administrate/base_dashboard"

module CodForm
  class ShopConfigDashboard < Administrate::BaseDashboard
    ATTRIBUTE_TYPES = {
      id: Field::Number,
      shop: Field::BelongsTo,
      shop_id: Field::Number,
      storefront_mode: Field::Select.with_options(searchable: false,
                                                  collection: ::CodForm::ShopConfig::STOREFRONT_MODES),
      module_access: Field::Select.with_options(searchable: false,
                                                collection: ::CodForm::ShopConfig::MODULE_ACCESS_VALUES),
      enabled_at: Field::DateTime,
      feature_overrides: JsonTextField.with_options(rows: 6),
      general: JsonTextField,
      fraud: JsonTextField,
      setup_state: JsonTextField,
      allowed_origins: JsonTextField,
      config_version: Field::Number,
      metafield_synced_version: Field::Number,
      metafield_synced_at: Field::DateTime,
      asset_base: Field::String,
      created_at: Field::DateTime,
      updated_at: Field::DateTime
    }.freeze

    COLLECTION_ATTRIBUTES = %i[
      id
      shop
      storefront_mode
      module_access
      enabled_at
      config_version
      metafield_synced_version
    ].freeze

    # preview_token is deliberately not shown.
    SHOW_PAGE_ATTRIBUTES = %i[
      id
      shop
      storefront_mode
      module_access
      enabled_at
      feature_overrides
      general
      fraud
      setup_state
      allowed_origins
      config_version
      metafield_synced_version
      metafield_synced_at
      asset_base
      created_at
      updated_at
    ].freeze

    # feature_overrides: JSON object {"<feature_key>": true|false}.
    FORM_ATTRIBUTES = %i[
      module_access
      feature_overrides
      storefront_mode
    ].freeze

    COLLECTION_FILTERS = {
      cod_form: ->(resources) { resources.where(storefront_mode: ::CodForm::ShopConfig::STOREFRONT_MODE_COD_FORM) },
      module_on: ->(resources) { resources.where(module_access: ::CodForm::ShopConfig::MODULE_ACCESS_ON) },
      module_off: ->(resources) { resources.where(module_access: ::CodForm::ShopConfig::MODULE_ACCESS_OFF) }
    }.freeze

    def display_resource(shop_config)
      "COD Form config (shop ##{shop_config.shop_id})"
    end
  end
end
