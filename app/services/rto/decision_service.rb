# frozen_string_literal: true

module Rto
  # RTO decision engine (v2).
  #
  # Reads the two pre-aggregated rows (customer + zip) and scores with
  # Rto::Scorer (Empirical-Bayes smoothing + additive log-odds). Fully O(1):
  # two indexed point lookups + arithmetic, cached per (identity, zip, value).
  #
  # Response is backward-compatible with v1 (status / cod_allowed / risk_score /
  # reason_codes / ttl_seconds) and adds `band`, `probability`, and `reasons`.
  class DecisionService < ApplicationService
    TTL_SECONDS = 120

    def initialize(shopify_domain:, phone:, email:, zip:, country: nil, cart: nil)
      @shopify_domain = shopify_domain.to_s.strip.downcase
      @phone   = phone
      @email   = email
      @zip     = zip.to_s.strip.presence
      @country = country.to_s.strip.presence
      @cart    = cart
    end

    def call
      # Short TTL: risk can change quickly as new outcomes arrive.
      Rails.cache.fetch(cache_key, expires_in: TTL_SECONDS) { compute_decision }
    end

    private

    def compute_decision
      pn = RtoOrder.normalize_phone(@phone)
      en = RtoOrder.normalize_email(@email)

      # Identity is keyed by phone first (unique), email as fallback.
      identity   = CustomerIdentity.find_by(phone_normalized: pn) if pn.present?
      identity ||= CustomerIdentity.find_by(email_normalized: en) if en.present?
      cust_stat  = identity && GlobalCustomerStat.find_by(customer_identity_id: identity.id)

      zip_stat =
        if @zip.present?
          GlobalZipStat.find_by(country: @country, zip: @zip) ||
            GlobalZipStat.find_by(country: nil, zip: @zip)
        end

      result = Rto::Scorer.call(
        cust:       cust_stat && { rto: cust_stat.rto, orders: cust_stat.total_orders },
        zip:        zip_stat  && { rto: zip_stat.rto,  orders: zip_stat.total_orders },
        value_band: value_band(@cart),
        mu:         global_rto_rate
      )

      {
        status:       "Success",
        cod_allowed:  result.cod_allowed,                       # false only for "high" band
        band:         result.band,                              # "low" | "medium" | "high"
        risk_score:   result.score,                             # 0..100
        probability:  result.probability,                       # 0.0..1.0
        reason_codes: result.reasons.map { |r| r[:code] },      # string array (v1-compatible)
        reasons:      result.reasons,                           # detailed: code/contribution/explanation
        ttl_seconds:  TTL_SECONDS
      }
    end

    def cache_key
      [
        "rto:decision:v2",
        @shopify_domain,
        RtoOrder.normalize_phone(@phone),
        RtoOrder.normalize_email(@email),
        @country,
        @zip,
        value_band(@cart)
      ].join(":")
    end

    # Bucket cart total into -1..2. Boundaries assume INR; tune per currency/shop.
    def value_band(cart)
      v = cart_total(cart).to_f
      return 0 if v <= 0

      case v
      when 0...800     then -1
      when 800...2500  then 0
      when 2500...6000 then 1
      else 2
      end
    end

    def cart_total(cart)
      case cart
      when Hash then cart[:total] || cart["total"] || cart[:total_price] || cart["total_price"]
      when Numeric, String then cart
      end
    end

    # Global bad/RTO rate, cached hourly. Falls back to the Scorer default.
    def global_rto_rate
      Rails.cache.fetch("rto:global_mu", expires_in: 1.hour) do
        total = GlobalZipStat.sum(:total_orders).to_i
        bad   = GlobalZipStat.sum(:rto).to_i
        total.positive? ? (bad.to_f / total).clamp(0.01, 0.9) : Rto::Scorer::GLOBAL_RTO_RATE
      end
    rescue StandardError
      Rto::Scorer::GLOBAL_RTO_RATE
    end
  end
end
