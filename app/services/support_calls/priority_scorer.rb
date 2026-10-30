# frozen_string_literal: true

module SupportCalls
  module PriorityScorer
    module_function

    WEIGHTS = {
      plan: 0.35,
      orders: 0.30,
      customers: 0.15,
      age: 0.20,
      value: 0.55,
      urgency: 0.45
    }.freeze

    CEILINGS = {
      plan: 2000,
      orders: 5000,
      customers: 20000,
      age: 1825
    }.freeze

    COOLDOWN_DAYS = 30
    SHORT_COOLDOWN_DAYS = 3
    RECONTACT_MULTIPLIER = 1.25

    def value_score(plan_value:, order_count:, customer_count:, age_days:)
      score =
        log_norm(plan_value, CEILINGS[:plan]) * WEIGHTS[:plan] +
        log_norm(order_count, CEILINGS[:orders]) * WEIGHTS[:orders] +
        log_norm(customer_count, CEILINGS[:customers]) * WEIGHTS[:customers] +
        log_norm(age_days, CEILINGS[:age]) * WEIGHTS[:age]
      score.round
    end

    def urgency_score(segment, **inputs)
      case segment
      when "churned" then churned_urgency(inputs)
      when "new_install" then new_install_urgency(inputs)
      when "active" then active_urgency(inputs)
      else 0
      end
    end

    def cps(value:, urgency:)
      (value * WEIGHTS[:value] + urgency * WEIGHTS[:urgency]).round
    end

    def churned_urgency(inputs)
      days = inputs[:days_since_uninstall].to_i
      if days <= 3 then 100
      elsif days <= 7 then 80
      elsif days <= 14 then 60
      elsif days <= 30 then 40
      elsif days <= 60 then 20
      else 10
      end
    end

    def new_install_urgency(inputs)
      days = inputs[:days_since_install].to_i
      base =
        if days <= 3 then 70
        elsif days <= 7 then 85
        elsif days <= 14 then 100
        elsif days <= 21 then 70
        else 45
        end
      base += 20 unless inputs[:activated]
      [base, 100].min
    end

    def active_urgency(inputs)
      case inputs[:churn_band].to_s
      when "critical" then 100
      when "at_risk" then 70
      when "watch" then 40
      else 10
      end
    end

    def log_norm(value, ceiling)
      v = value.to_f
      return 0.0 if v <= 0

      ratio = Math.log10(1 + v) / Math.log10(1 + ceiling.to_f)
      [[ratio, 0.0].max, 1.0].min * 100
    end
  end
end
