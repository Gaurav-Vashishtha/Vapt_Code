# frozen_string_literal: true

module CodFormAdmin
  # Form integrations (D.15, B.18): google_sheets, klaviyo, omnisend, rabbitpay.
  # `credentials` are write-only and never serialised.
  class IntegrationsController < BaseController
    GATES = { "google_sheets" => "google_sheets", "klaviyo" => "klaviyo_omnisend", "omnisend" => "klaviyo_omnisend" }.freeze
    CREDENTIAL_KEYS = { "klaviyo" => %w[private_api_key], "omnisend" => %w[api_key] }.freeze
    # I.5 column keys available for the Google Sheets mapping; custom fields are "custom:<field key>".
    SHEET_COLUMNS = %w[order_name order_id created_at first_name last_name phone email address1 address2 city
                       province zip country items quantity subtotal discount shipping cod_fee total currency
                       shipping_rate discount_code utm_source utm_medium utm_campaign note].freeze
    CUSTOM_COLUMN = /\Acustom:cf_[a-z0-9]{8}\z/.freeze

    def index
      rows = CodForm::Integration.where(shop_id: @shop.id).index_by(&:provider)
      render json: { "items" => CodForm::Integration::PROVIDERS.map { |provider| item_json(provider, rows[provider]) } }
    end

    # PUT /cod_form/integrations/:provider  {"credentials": {...}, "config": {...}}
    def update
      provider = provider_param
      gate!(GATES[provider]) if GATES[provider]
      integration = CodForm::Integration.for(@shop, provider)
      errors = Validators::Util.errors

      attrs = {}
      attrs[:config] = config_for(provider, body_hash("config"), integration.config, errors) if body.key?("config")
      if body.key?("credentials") && CREDENTIAL_KEYS[provider]
        credentials = credentials_for(provider, body_hash("credentials"), errors)
        attrs[:credentials] = credentials
        attrs[:status] = credentials.empty? ? CodForm::Integration::STATUS_DISCONNECTED : CodForm::Integration::STATUS_CONNECTED
        attrs[:last_error] = nil
      end
      attrs[:status] = CodForm::Integration::STATUS_CONNECTED if provider == "rabbitpay" && attrs[:config]
      clean = errors.reject { |_, list| list.empty? }
      raise ValidationError.new(clean) if clean.any?

      old_config = integration.config
      integration.update!(attrs)
      audit_changes("integration.#{provider}.config", old_config, integration.config)
      audit("integration.#{provider}.credentials", "", "[changed]") if attrs.key?(:credentials)
      bump! if provider == "rabbitpay" # the session tells the form a pay-online handler is expected
      render json: item_json(provider, integration)
    end

    def destroy
      provider = provider_param
      integration = CodForm::Integration.find_by(shop_id: @shop.id, provider: provider)
      if integration
        integration.disconnect!
        audit("integration.#{provider}.status", "connected", "disconnected")
      end
      head :no_content
    end

    private

    def provider_param
      provider = params[:provider].to_s
      raise ActiveRecord::RecordNotFound unless CodForm::Integration::PROVIDERS.include?(provider)

      provider
    end

    def item_json(provider, integration)
      {
        "provider" => provider,
        "status" => integration&.status || CodForm::Integration::STATUS_DISCONNECTED,
        "config" => integration&.config || {},
        "last_error" => integration&.last_error,
        "last_success_at" => iso(integration&.last_success_at),
        "available" => available?(provider)
      }
    end

    def available?(provider)
      return false if GATES[provider] && !gate_allowed?(GATES[provider])
      return ENV["GOOGLE_SHEETS_CLIENT_ID"].present? if provider == "google_sheets"

      true
    end

    def credentials_for(provider, raw, errors)
      raw ||= {}
      CREDENTIAL_KEYS.fetch(provider).each_with_object({}) do |key, out|
        value = raw[key]
        next if value.nil? || value == ""

        if value.is_a?(String) && value.strip.length.between?(8, 500)
          out[key] = value.strip
        else
          errors["credentials.#{key}"] << "is not a valid key"
        end
      end
    end

    def config_for(provider, raw, current, errors)
      raw ||= {}
      case provider
      when "google_sheets"
        columns = raw.key?("columns") ? raw["columns"] : current["columns"]
        columns = Array(columns).map(&:to_s)
        unknown = columns.reject { |column| SHEET_COLUMNS.include?(column) || column.match?(CUSTOM_COLUMN) }
        errors["config.columns"] << "unknown column: #{unknown.first(5).join(', ')}" if unknown.any?
        errors["config.columns"] << "has too many columns (maximum 60)" if columns.size > 60
        {
          "spreadsheet_id" => Validators::Util.string(raw.fetch("spreadsheet_id", current["spreadsheet_id"]), "config.spreadsheet_id", errors, "", max: 200),
          "sheet_name" => Validators::Util.string(raw.fetch("sheet_name", current["sheet_name"]), "config.sheet_name", errors, "", max: 100),
          "columns" => columns.uniq
        }
      when "klaviyo", "omnisend"
        events = Validators::Util.hash(raw["events"])
        stored = Validators::Util.hash(current["events"])
        { "events" => %w[order abandoned].each_with_object({}) do |key, out|
          out[key] = Validators::Util.bool(events.fetch(key, stored.fetch(key, true)), "config.events.#{key}", errors, true)
        end }
      else # rabbitpay: interface only (PRE-6)
        { "enabled" => Validators::Util.bool(raw.fetch("enabled", current["enabled"] == true), "config.enabled", errors, false) }
      end
    end
  end
end
