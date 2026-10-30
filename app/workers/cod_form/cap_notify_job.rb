# frozen_string_literal: true

module CodForm
  # CodForm::CapNotifyJob.perform_async(shop_id, period)   (K.9, CAP-8, ARCHITECTURE.md I.6)
  #
  # Sends the usage notices: at 50 %, at 80 % and at the cap (100 %), once each per period.
  # "Once" is an atomic claim of form_order_usages.notified_50_at / notified_80_at /
  # notified_100_at (UPDATE … WHERE notified_x_at IS NULL), so concurrent jobs send one email.
  # The 80 and 100 timestamps are also the in-app flags the usage card reads through
  # GET /cod_form/usage. A shop that jumps past several marks at once gets only the highest one.
  class CapNotifyJob < ApplicationJob
    sidekiq_options queue: "default", retry: 3

    DEFAULT_THRESHOLDS = [50, 80, 100].freeze
    # Lowest mark first. The mail level is what CodFormMailer.usage_notice takes.
    STEPS = [[:notified_50_at, 50], [:notified_80_at, 80], [:notified_100_at, 100]].freeze

    def perform(shop_id, period)
      shop = Shop.find_by(id: shop_id)
      return if shop.nil?

      usage = CodForm::OrderUsage.find_by(shop_id: shop.id, period: period.to_s)
      return if usage.nil?

      state = CodForm::CapService.state(shop, fresh: true)
      cap = state["cap"]
      return unless cap.is_a?(Integer) && cap.positive?
      return unless state["period"].to_s == period.to_s # a late job for an old period sends nothing

      percent = usage.orders_count.to_i * 100.0 / cap
      reached = self.class.steps(thresholds).select { |_, _, mark| percent >= mark }
      return if reached.empty?

      column, level, = reached.last
      CodForm::OrderUsage.where(id: usage.id, cap_snapshot: nil).update_all(cap_snapshot: cap) if level == 100
      reached[0...-1].each { |lower, _, _| claim(usage, lower) } # no late mail for a lower mark
      deliver(shop, level) if claim(usage, column)
    end

    # [[column, mail level, percent]] for a list of percentages: the highest is the cap notice,
    # the ones below it are warnings (at most two, the two highest).
    #   [50, 80, 100] => 50 %, 80 %, 100 %      [80, 100] => 80 %, 100 %      [100] => 100 %
    def self.steps(list)
      list = Array(list).map(&:to_i).select { |n| n.between?(1, 100) }.uniq.sort.last(3)
      list = DEFAULT_THRESHOLDS if list.empty?
      STEPS.last(list.size).zip(list).map { |(column, level), mark| [column, level, mark] }
    end

    private

    # cod_form_global_settings.usage_notice_thresholds (default [50, 80, 100]).
    def thresholds
      CodForm::GlobalSetting.current.usage_notice_thresholds
    end

    def claim(usage, column)
      return false unless CodForm::OrderUsage.column_names.include?(column.to_s) # before the migration

      CodForm::OrderUsage.where(id: usage.id, column => nil).update_all(column => Time.current) == 1
    end

    def deliver(shop, level)
      return if shop.owner_email.blank?

      CodFormMailer.usage_notice(shop.id, level).deliver_now
    end
  end
end
