# frozen_string_literal: true

module CodFormAdmin
  # GET /cod_form/usage — usage against the monthly cap (CAP-8) for the Setup usage card, the
  # Summary meter and the Billing rows.
  class UsageController < BaseController
    HISTORY_MONTHS = 12

    def show
      state = CodForm::CapService.state(@shop)
      period = state["period"] || CodForm::CapService.period_for(@shop, Time.current)
      row = CodForm::OrderUsage.for(@shop.id, period)
      history = CodForm::OrderUsage.where(shop_id: @shop.id).order(period: :desc).limit(HISTORY_MONTHS)

      render json: {
        "period" => period,
        "orders" => state["orders"].to_i,
        "partial_orders" => row.partial_orders_count.to_i,
        "cap" => state["cap"],
        "state" => state["state"],
        "behaviour" => state["behaviour"],
        "grace_orders" => state["grace_orders"],
        "percent" => state["percent"],
        "overage" => {
          "rate" => state["overage_rate"],
          "count" => row.over_cap_count.to_i,
          "billed" => row.overage_billed_count.to_i
        },
        "history" => history.map { |usage| { "period" => usage.period, "orders" => usage.orders_count.to_i } }
      }
    end
  end
end
