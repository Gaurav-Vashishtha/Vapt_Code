# frozen_string_literal: true

module CodForm
  # CAP-9 (ARCHITECTURE.md J.2). sidekiq-cron: daily 02:30 UTC, queue administration.
  #
  # Built but INERT: nothing is counted and nothing is billed unless a plan_limits row that
  # applies to the shop has an `overage_rate`. No rate is seeded (product decision 8).
  #
  #   record_over_cap!(shop)  - called by PostOrderJob after each real form order: when the shop
  #                             pays for a plan, a rate is set and the order is beyond the cap,
  #                             over_cap_count += 1.
  #   perform                 - bills (over_cap_count - overage_billed_count) x rate through the
  #                             existing ShopifyServices::UsageChargeApplyService.
  #
  # Double billing is prevented by claiming the count BEFORE charging (one guarded UPDATE) and
  # giving it back when the charge fails; a crash between the two can only under-bill.
  class OverageBillingJob < ApplicationJob
    sidekiq_options queue: "administration", retry: false

    PERIODS_BACK = 2 # current and previous month

    # Returns the new over_cap_count, or nil when nothing was counted.
    def self.record_over_cap!(shop)
      return nil if shop.charge_id.blank? # free shops are never billed

      state = CodForm::CapService.state(shop, fresh: true)
      rate = state["overage_rate"].to_f
      cap = state["cap"]
      return nil unless rate.positive? && cap.is_a?(Integer)
      return nil unless state["orders"].to_i > cap

      CodForm::OrderUsage.increment!(shop_id: shop.id, period: state["period"], column: :over_cap_count)
    end

    def perform
      periods = (0...PERIODS_BACK).map { |i| (Time.current.utc - i.months).strftime("%Y-%m") }
      # A shop east of UTC can already be in the next month.
      periods << (Time.current.utc + 1.day).strftime("%Y-%m")

      CodForm::OrderUsage.where(period: periods.uniq)
                         .where("over_cap_count > overage_billed_count")
                         .find_each do |usage|
        bill(usage)
      rescue StandardError => e
        Rails.logger.error("[codf/overage] usage=#{usage.id} shop=#{usage.shop_id} failed: #{e.class}")
      end
    end

    private

    def bill(usage)
      shop = Shop.find_by(id: usage.shop_id)
      return if shop.nil? || shop.charge_id.blank?

      rate = CodForm::CapService.state(shop, fresh: true)["overage_rate"].to_f
      return unless rate.positive? # rate removed: leave the count, bill nothing

      billed_before = usage.overage_billed_count.to_i
      quantity = usage.over_cap_count.to_i - billed_before
      return unless quantity.positive?

      amount = (quantity * rate).round(2)
      return unless amount.positive?

      claimed = CodForm::OrderUsage.where(id: usage.id, overage_billed_count: billed_before)
                                   .update_all(["overage_billed_count = overage_billed_count + ?, updated_at = ?", quantity, Time.current])
      return unless claimed == 1

      result = ShopifyServices::UsageChargeApplyService.call(
        shop.shopify_domain, amount, description: "COD Form extra orders (#{usage.period})"
      )
      if result.is_a?(Hash) && result[:success]
        Rails.logger.info("[codf/overage] shop=#{shop.id} period=#{usage.period} orders=#{quantity} amount=#{amount}")
      else
        release(usage, quantity)
        reason = result.is_a?(Hash) ? result[:reason] : "unknown"
        # capped_amount_exhausted and the other reasons are retried by tomorrow's run.
        Rails.logger.warn("[codf/overage] shop=#{shop.id} period=#{usage.period} not billed reason=#{reason}")
      end
    rescue StandardError
      release(usage, quantity) if claimed == 1 && !(result.is_a?(Hash) && result[:success])
      raise
    end

    def release(usage, quantity)
      CodForm::OrderUsage.where(id: usage.id)
                         .update_all(["overage_billed_count = GREATEST(overage_billed_count - ?, 0), updated_at = ?", quantity, Time.current])
    end
  end
end
