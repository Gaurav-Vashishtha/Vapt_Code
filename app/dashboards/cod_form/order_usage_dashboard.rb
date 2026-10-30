# frozen_string_literal: true

require "administrate/base_dashboard"

module CodForm
  # Read-only (routes: index, show).
  class OrderUsageDashboard < Administrate::BaseDashboard
    ATTRIBUTE_TYPES = {
      id: Field::Number,
      shop: Field::BelongsTo,
      shop_id: Field::Number,
      period: Field::String,
      orders_count: Field::Number,
      partial_orders_count: Field::Number,
      test_orders_count: Field::Number,
      over_cap_count: Field::Number,
      overage_billed_count: Field::Number,
      cap_snapshot: Field::Number,
      notified_80_at: Field::DateTime,
      notified_100_at: Field::DateTime,
      created_at: Field::DateTime,
      updated_at: Field::DateTime
    }.freeze

    COLLECTION_ATTRIBUTES = %i[
      id
      shop
      period
      orders_count
      partial_orders_count
      test_orders_count
      over_cap_count
      cap_snapshot
    ].freeze

    SHOW_PAGE_ATTRIBUTES = %i[
      id
      shop
      period
      orders_count
      partial_orders_count
      test_orders_count
      over_cap_count
      overage_billed_count
      cap_snapshot
      notified_80_at
      notified_100_at
      created_at
      updated_at
    ].freeze

    FORM_ATTRIBUTES = [].freeze

    COLLECTION_FILTERS = {
      over_cap: ->(resources) { resources.where("over_cap_count > 0") }
    }.freeze

    def display_resource(order_usage)
      "Form usage #{order_usage.period} (shop ##{order_usage.shop_id})"
    end
  end
end
