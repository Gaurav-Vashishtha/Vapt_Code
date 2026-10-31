# frozen_string_literal: true

module Rto
  # Pure RTO scoring math. No DB, no cache — trivially unit-testable.
  #
  # Approach:
  #   1. Empirical-Bayes (Beta-Binomial) smoothing turns raw counts into a
  #      trustworthy rate that shrinks toward the global base rate on thin data.
  #   2. Additive log-odds (weight-of-evidence) combines the customer and zip
  #      signals in the one space where combining evidence is just addition.
  #
  # Both are pure arithmetic on counts already stored in global_*_stats.
  class Scorer
    # --- Tunables (override via ENV; estimate from data — see design doc §6) ---
    GLOBAL_RTO_RATE = (ENV.fetch("RTO_GLOBAL_RATE", nil) || 0.22).to_f  # mu : global bad/RTO rate
    K_CUST          = (ENV.fetch("RTO_K_CUST", nil)      || 8).to_f     # prior strength, customer
    K_ZIP           = (ENV.fetch("RTO_K_ZIP", nil)       || 40).to_f    # prior strength, pincode

    W_BASE = (ENV.fetch("RTO_W_BASE", nil) || 1.0).to_f
    W_CUST = (ENV.fetch("RTO_W_CUST", nil) || 1.0).to_f
    W_ZIP  = (ENV.fetch("RTO_W_ZIP", nil)  || 0.7).to_f
    W_VAL  = (ENV.fetch("RTO_W_VAL", nil)  || 0.5).to_f

    # score (0..100) -> action cutoffs. Override per call (per-shop) if needed.
    MEDIUM_AT = (ENV.fetch("RTO_MEDIUM_AT", nil) || 30).to_i
    HIGH_AT   = (ENV.fetch("RTO_HIGH_AT", nil)   || 60).to_i

    Result = Struct.new(
      :probability, :score, :band, :cod_allowed, :reasons, keyword_init: true
    )

    # cust / zip are hashes like { rto: Integer, orders: Integer } or nil.
    # value_band: -1 low .. 0 normal .. 1 high .. 2 very-high (bucket cart total).
    def self.call(cust:, zip:, value_band: 0, mu: GLOBAL_RTO_RATE,
                  medium_at: MEDIUM_AT, high_at: HIGH_AT)
      base    = logit(mu)
      l       = W_BASE * base
      reasons = []

      # --- customer signal ---
      if history?(cust)
        rate = eb_rate(cust[:rto].to_i, cust[:orders].to_i, K_CUST, mu)
        d    = W_CUST * (logit(rate) - base)
        l   += d
        reasons << reason("customer_history", d,
                          "#{cust[:rto].to_i}/#{cust[:orders].to_i} orders bad (smoothed #{pct(rate)})")
      else
        reasons << reason("customer_no_history", 0.0, "no prior order history")
      end

      # --- pincode signal ---
      if history?(zip)
        rate = eb_rate(zip[:rto].to_i, zip[:orders].to_i, K_ZIP, mu)
        d    = W_ZIP * (logit(rate) - base)
        l   += d
        if d.abs > 0.15
          reasons << reason("zip_history", d,
                            "#{zip[:rto].to_i}/#{zip[:orders].to_i} zip orders bad (smoothed #{pct(rate)})")
        end
      end

      # --- cart value signal (high-value COD is refused more) ---
      vb = value_band.to_i
      if vb != 0
        d  = W_VAL * (0.4 * vb)
        l += d
        reasons << reason("high_cart_value", d, "cart value band #{vb}") if vb.positive?
      end

      p     = sigmoid(l)
      score = (p * 100).round
      band  =
        if score >= high_at then "high"
        elsif score >= medium_at then "medium"
        else "low"
        end

      Result.new(
        probability: p.round(4),
        score:       score,
        band:        band,
        cod_allowed: band != "high",             # medium still shows COD (with friction)
        reasons:     reasons.sort_by { |r| -r[:contribution].abs }
      )
    end

    # Weighted log-odds contribution for a single entity — persisted on the
    # global_*_stats row so dashboards can sort/segment by risk. See
    # StatsUpdaterService. Returns [smoothed_rate, weighted_logit_contribution].
    def self.entity_contribution(rto:, orders:, k:, weight:, mu: GLOBAL_RTO_RATE)
      return [nil, 0.0] unless orders.to_i.positive?

      rate = eb_rate(rto.to_i, orders.to_i, k, mu)
      [rate, weight * (logit(rate) - logit(mu))]
    end

    # --- Empirical-Bayes (Beta-Binomial) smoothed rate ---
    def self.eb_rate(r, n, k, mu)
      a = mu * k
      b = (1.0 - mu) * k
      (r + a) / (n + a + b)
    end

    def self.logit(p)
      p = p.clamp(1e-6, 1 - 1e-6)
      Math.log(p / (1 - p))
    end

    def self.sigmoid(x)
      1.0 / (1.0 + Math.exp(-x))
    end

    def self.history?(h)
      h.is_a?(Hash) && h[:orders].to_i.positive?
    end

    def self.pct(x)
      "#{(x * 100).round}%"
    end

    def self.reason(code, contribution, explanation)
      { code: code, contribution: contribution.round(3), explanation: explanation }
    end
  end
end
