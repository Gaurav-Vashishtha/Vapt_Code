# frozen_string_literal: true

class RtoController < ApiController
  # Public scoring endpoint for storefront script.
  # POST /rto/decision
  #
  # Body (JSON):
  # - shopify_domain
  # - phone (optional)
  # - email (optional)
  # - zip (optional)
  # - country (optional)
  # - cart (optional, free-form)
  def decision
    payload = params.to_unsafe_h
    domain = payload["shopify_domain"].presence || payload["shop"].presence || payload["domain"].presence
    if domain.blank?
      render json: { status: "Error", message: "shopify_domain is required" }, status: :bad_request
      return
    end

    phone = payload["phone"]
    email = payload["email"]
    zip = payload["zip"]
    country = payload["country"]

    result = Rto::DecisionService.call(
      shopify_domain: domain,
      phone: phone,
      email: email,
      zip: zip,
      country: country,
      cart: payload["cart"]
    )

    render json: result, status: :ok
  rescue => e
    SlackNotifyJob.perform_async(
      ":warning: (#{Rails.env})\nRTO decision error\nDomain: #{params[:shopify_domain] || params[:shop] || params[:domain]}\n#{e.class}: #{e.message}"
    )
    render json: { status: "Error", message: "Unable to score request" }, status: :internal_server_error
  end
end

