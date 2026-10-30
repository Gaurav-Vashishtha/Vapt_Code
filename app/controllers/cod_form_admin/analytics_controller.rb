# frozen_string_literal: true

module CodFormAdmin
  # COD Form analytics tab (D.15, ANL-1..4). This controller only checks gates and parameters and
  # shapes the response; the queries are CodForm::Analytics::Query (WS8, K.9).
  class AnalyticsController < BaseController
    DATE = /\A\d{4}-\d{2}-\d{2}\z/.freeze
    DEVICES = %w[mobile tablet desktop].freeze
    BREAKDOWNS = %w[utm_campaign offer country device product form].freeze

    # GET /cod_form/analytics?from=&to=&country=&device=&product_id=&compare=1
    def show
      gate!("basic_analytics")
      render json: CodForm::Analytics::Query.summary(@shop, from: date(:from), to: date(:to), filters: filters,
                                                            compare: params[:compare].to_s == "1")
    end

    # GET /cod_form/analytics/sessions?from=&to=&country=&device=&recent=50
    # Live from the sessions table: totals, per day, by source / device / country, latest sessions.
    def sessions
      gate!("basic_analytics")
      recent = params.key?(:recent) ? params[:recent].to_i : 50
      render json: CodForm::Analytics::SessionStats.call(@shop, from: date(:from), to: date(:to),
                                                               filters: filters.slice("country", "device"), recent: recent)
    end

    # GET /cod_form/analytics/breakdown?by=utm_campaign|offer|country|device|product|form&from=&to=
    def breakdown
      gate!("advanced_analytics")
      by = params[:by].to_s
      invalid!("by", "must be one of: #{BREAKDOWNS.join(', ')}") unless BREAKDOWNS.include?(by)

      render json: CodForm::Analytics::Query.breakdown(@shop, by: by, from: date(:from), to: date(:to))
    end

    # GET /cod_form/analytics/export.csv?… (same parameters as show; `by` exports a breakdown)
    def export
      gate!("advanced_analytics")
      by = params[:by].to_s
      invalid!("by", "must be one of: #{BREAKDOWNS.join(', ')}") unless by.empty? || BREAKDOWNS.include?(by)

      csv = CodForm::Analytics::Query.export_csv(@shop, from: date(:from), to: date(:to), filters: filters, by: by.presence)
      send_data csv, type: "text/csv; charset=utf-8", disposition: "attachment",
                     filename: "cod-form-analytics-#{Time.current.utc.strftime('%Y%m%d')}.csv"
    end

    private

    def date(key)
      value = params[key].to_s
      return nil unless value.match?(DATE)

      Date.iso8601(value)
    rescue ArgumentError
      nil
    end

    def filters
      out = {}
      country = params[:country].to_s.strip.upcase
      out["country"] = country if country.match?(/\A[A-Z]{2}\z/)
      device = params[:device].to_s
      out["device"] = device if DEVICES.include?(device)
      product_id = Validators::Util.shopify_id(params[:product_id])
      out["product_id"] = product_id if product_id
      out
    end
  end
end
