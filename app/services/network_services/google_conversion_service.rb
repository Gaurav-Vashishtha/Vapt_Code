# frozen_string_literal: true

module NetworkServices
  class GoogleConversionService
    UPLOAD_PATH_TEMPLATE = "https://googleads.googleapis.com/v19/customers/%s:uploadClickConversions"
    # Full resource name: customers/{customer_id}/conversionActions/{conversion_action_id}
    RESOURCE_PATTERN = %r{\Acustomers/(\d+)/conversionActions/(.+)\z}

    # Extracts key Google click / campaign parameters from Shopify's landing_site URL.
    # Example landing_site:
    # /products/foo?gad_campaignid=21370949456&gad_source=1&gclid=XYZ123&...
    def self.params_from_landing_site(landing_site)
      return {} if landing_site.blank?

      uri = URI.parse(landing_site.to_s) rescue nil
      query = uri&.query || landing_site.to_s.split("?", 2)[1]
      return {} if query.blank?

      pairs = Rack::Utils.parse_nested_query(query) rescue CGI.parse(query)
      flat = pairs.transform_values { |v| Array(v).first }

      {
        gclid: flat["gclid"].to_s.strip.presence,
        gbraid: flat["gbraid"].to_s.strip.presence,
        wbraid: flat["wbraid"].to_s.strip.presence,
        gad_campaignid: flat["gad_campaignid"].to_s.strip.presence,
        gad_source: flat["gad_source"].to_s.strip.presence
      }.compact
    end

    # Backwards-compatible helper used elsewhere.
    def self.gclid_from_landing_site(landing_site)
      params_from_landing_site(landing_site)[:gclid]
    end

    def initialize(setting, options = {})
      @setting = setting
      @gclid = options[:gclid]
      @gbraid = options[:gbraid]
      @wbraid = options[:wbraid]
      @gad_campaignid = options[:gad_campaignid]
      @gad_source = options[:gad_source]
      @conversion_value = options[:value].to_f
      @order_id = options[:order_id].to_s.presence
      @currency_code = options[:currency_code].to_s.presence || "INR"

      @conversion_action = @setting.google_conversion_id.to_s.strip.presence
      @access_token = @setting.google_conversion_token.to_s.strip.presence
    end

    # Full purchase conversion (e.g. COD order placed).
    def self.call_purchase(order, setting, gclid: nil)
      return { "error" => "Google Ads conversion not enabled" } unless setting&.conversion_tracking != false

      value = if order.respond_to?(:total_price)
                order.total_price.to_s.to_f
              elsif order.respond_to?(:totalPrice)
                order.totalPrice.to_s.to_f
              else
                (order[:total_price] || order["total_price"]).to_s.to_f
              end

      currency = if order.respond_to?(:currency)
                   order.currency.to_s.presence
                 elsif order.respond_to?(:currencyCode)
                   order.currencyCode.to_s.presence
                 else
                   (order[:currency_code] || order["currency_code"] || order[:currency] || order["currency"]).to_s.presence
                 end
      currency = "INR" if currency.blank?

      order_id = if order.respond_to?(:id)
                   order.id.to_s
                 else
                   (order[:id] || order["id"]).to_s.presence
                 end

      new(setting, value: value, gclid: gclid, order_id: order_id, currency_code: currency).upload_conversion
    end

    # Partial payment conversion (remaining amount for partial-payment orders).
    def self.call_partial(order, conversion_value, setting, order_id: nil, gclid: nil)
      return { "error" => "Google Ads conversion not enabled" } unless setting&.conversion_tracking != false

      order_id = order_id.to_s.presence
      order_id ||= order.respond_to?(:id) ? order.id.to_s : (order[:id] || order["id"]).to_s.presence

      currency = if order.respond_to?(:currency)
                   order.currency.to_s.presence
                 elsif order.respond_to?(:currencyCode)
                   order.currencyCode.to_s.presence
                 else
                   (order[:currency_code] || order["currency_code"] || order[:currency] || order["currency"]).to_s.presence
                 end
      currency = "INR" if currency.blank?

      new(setting, value: conversion_value, order_id: order_id, currency_code: currency, gclid: gclid).upload_conversion
    end

    def upload_conversion
      if @conversion_action.blank?
        return { "error" => "Conversion ID (Conversion Action resource name) is not configured" }
      end
      if @access_token.blank?
        return { "error" => "Conversions API token is not configured" }
      end

      customer_id = customer_id_from_resource(@conversion_action)
      unless customer_id
        return { "error" => "Conversion ID must be the full resource name (e.g. customers/1234567890/conversionActions/555666777)" }
      end

      developer_token = ENV["GOOGLE_ADS_DEVELOPER_TOKEN"].to_s.presence
      if developer_token.blank?
        Rails.logger.warn "GoogleConversionService: GOOGLE_ADS_DEVELOPER_TOKEN not set; request may fail"
      end

      payload = {
        conversions: [{
          conversionAction: @conversion_action,
          conversionDateTime: Time.current.strftime("%Y-%m-%d %H:%M:%S%:z"),
          conversionValue: @conversion_value,
          currencyCode: @currency_code,
          orderId: @order_id
        }.tap do |h|
          h[:gclid] = @gclid if @gclid.present?
          h[:gbraid] = @gbraid if @gbraid.present?
          h[:wbraid] = @wbraid if @wbraid.present?
          # gad_campaignid / gad_source are GA4 tagging parameters and are not
          # fields on ClickConversion; we log them for debugging only.
          if @gad_campaignid.present? || @gad_source.present?
            Rails.logger.info "GoogleConversionService extra campaign params: gad_campaignid=#{@gad_campaignid.inspect}, gad_source=#{@gad_source.inspect}"
          end
        end],
        partialFailure: true
      }

      url = URI(format(UPLOAD_PATH_TEMPLATE, customer_id))

      request = Net::HTTP::Post.new(url)
      request["Authorization"] = "Bearer #{@access_token}"
      request["developer-token"] = developer_token if developer_token.present?
      request["Content-Type"] = "application/json"
      request.body = payload.to_json

      response = Net::HTTP.start(url.host, url.port, use_ssl: true) { |http| http.request(request) }
      body = response.body.presence || "{}"

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn "GoogleConversionService API error: #{response.code} #{body}"
        return { "error" => "Google Ads API returned #{response.code}", "body" => body }
      end

      JSON.parse(body)
    rescue JSON::ParserError => e
      Rails.logger.warn "GoogleConversionService JSON parse error: #{e.message}"
      { "error" => "Invalid API response", "raw" => body }
    rescue StandardError => e
      Rails.logger.error "GoogleConversionService error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      { "error" => e.message }
    end

    private

    def customer_id_from_resource(resource_name)
      return nil if resource_name.blank?
      m = resource_name.strip.match(RESOURCE_PATTERN)
      m ? m[1] : nil
    end
  end
end
