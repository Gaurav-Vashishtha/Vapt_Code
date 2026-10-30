# frozen_string_literal: true

module Rto
  class StatsUpdaterService < ApplicationService
    def initialize(order:, identity: nil)
      @order = order
      @identity = identity
    end

    def call
      update_customer_stats! if @identity.present?
      update_zip_stats!
      true
    end

    private

    def update_customer_stats!
      stat = GlobalCustomerStat.find_or_initialize_by(customer_identity: @identity)
      stat.total_orders = count_orders_for_identity
      stat.cod_orders = count_orders_for_identity(cod_only: true)
      stat.delivered = count_orders_for_identity(outcome: "delivered")
      # "Negative" outcomes: treat returned/cancelled/refunded as returns, and include RTO separately.
      stat.returned = count_orders_for_identity(outcome: "returned_or_cancelled_or_refunded")
      stat.rto = count_orders_for_identity(outcome: "rto_or_negative")
      stat.cancelled = count_orders_for_identity(outcome: "cancelled")
      stat.refunded = count_orders_for_identity(outcome: "refunded")
      stat.last_order_at = latest_order_time_for_identity
      apply_risk_fields!(stat, k: Rto::Scorer::K_CUST, weight: Rto::Scorer::W_CUST)
      stat.save!
    end

    def update_zip_stats!
      zip = @order.zip.to_s.strip
      return if zip.blank?

      country = @order.country.to_s.strip.presence
      stat = GlobalZipStat.find_or_initialize_by(country: country, zip: zip)
      scope = RtoOrder.where(zip: zip)
      scope = scope.where(country: country) if country.present?

      stat.total_orders = scope.count
      stat.cod_orders = scope.where(is_cod: true).count
      stat.delivered = scope.where(outcome_status: "delivered").count
      # "Negative" outcomes: treat returned/cancelled/refunded as returns, and include RTO separately.
      stat.returned = scope.where(outcome_status: %w[returned cancelled refunded]).or(scope.where(is_refunded: true)).distinct.count
      stat.rto = scope.where(outcome_status: %w[rto returned cancelled refunded]).or(scope.where(is_refunded: true)).distinct.count
      stat.cancelled = scope.where(outcome_status: "cancelled").count
      stat.refunded = scope.where(is_refunded: true).count
      stat.last_order_at = scope.maximum(:shopify_created_at)
      apply_risk_fields!(stat, k: Rto::Scorer::K_ZIP, weight: Rto::Scorer::W_ZIP)
      stat.save!
    end

    # Persist the smoothed rate + weighted log-odds contribution so dashboards
    # can rank by risk and a future read path can skip per-request smoothing.
    # Guarded so the service still works before the columns migration is run.
    def apply_risk_fields!(stat, k:, weight:)
      return unless stat.respond_to?(:rto_logit_contribution)

      rate, contribution = Rto::Scorer.entity_contribution(
        rto: stat.rto, orders: stat.total_orders, k: k, weight: weight
      )
      stat.smoothed_rto_rate = rate
      stat.rto_logit_contribution = contribution
      stat.score_computed_at = Time.current
    end

    def identity_scope
      pn = @identity.phone_normalized
      en = @identity.email_normalized

      scope = RtoOrder.all
      if pn.present? && en.present?
        scope.where(phone_normalized: pn).or(scope.where(email_normalized: en))
      elsif pn.present?
        scope.where(phone_normalized: pn)
      elsif en.present?
        scope.where(email_normalized: en)
      else
        RtoOrder.none
      end
    end

    def count_orders_for_identity(cod_only: false, outcome: nil)
      scope = identity_scope
      scope = scope.where(is_cod: true) if cod_only
      scope =
        case outcome
        when "delivered" then scope.where(outcome_status: "delivered")
        when "returned_or_cancelled_or_refunded"
          scope.where(outcome_status: %w[returned cancelled refunded]).or(scope.where(is_refunded: true)).distinct
        when "rto_or_negative"
          scope.where(outcome_status: %w[rto returned cancelled refunded]).or(scope.where(is_refunded: true)).distinct
        when "cancelled" then scope.where(outcome_status: "cancelled")
        when "refunded" then scope.where(is_refunded: true)
        else scope
        end
      scope.count
    end

    def latest_order_time_for_identity
      identity_scope.maximum(:shopify_created_at)
    end
  end
end
