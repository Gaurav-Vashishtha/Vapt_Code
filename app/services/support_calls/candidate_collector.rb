# frozen_string_literal: true

module SupportCalls
  class CandidateCollector
    WORKING_SET = 1500
    CHURN_LOOKBACK_DAYS = 90
    NEW_INSTALL_WINDOW_DAYS = 30

    def initialize(reference_date: Date.current)
      @today = reference_date
      @shop_cols = Shop.column_names.to_set
      @uninstalled_cols = UninstalledShop.column_names.to_set
      @plans = Plan.all.to_a
      @paid_plan_ids = @plans.select { |p| p.price.to_f.positive? }.map(&:id)
      @price_by_id = @plans.each_with_object({}) { |p, h| h[p.id] = p.price.to_f }
      @price_by_name = @plans.each_with_object({}) { |p, h| h[p.name.to_s.downcase] = p.price.to_f }
    end

    def new_installs
      scope = Shop.where("created_at >= ?", @today - NEW_INSTALL_WINDOW_DAYS.days)
      scope = paid_shop_scope(scope).order(created_at: :desc).limit(WORKING_SET)
      scope.filter_map { |shop| new_install_candidate(shop) }
    end

    def active
      scope = paid_shop_scope(Shop.all)
      scope = if @shop_cols.include?("churn_risk_score")
                scope.order(Arel.sql("churn_risk_score DESC NULLS LAST, customer_count DESC NULLS LAST"))
              else
                scope.order(Arel.sql("customer_count DESC NULLS LAST, max_orders DESC NULLS LAST"))
              end
      scope.limit(WORKING_SET).filter_map { |shop| active_candidate(shop) }
    end

    def churned
      scope = UninstalledShop.where("created_at >= ?", @today - CHURN_LOOKBACK_DAYS.days)
      if @uninstalled_cols.include?("plan_name_at_uninstall")
        scope = scope.where.not(plan_name_at_uninstall: [nil, ""]).where("plan_name_at_uninstall NOT ILIKE ?", "%free%")
      end
      scope = scope.order(created_at: :desc).limit(WORKING_SET).to_a

      domains = scope.map(&:shop_domain).compact.uniq
      reinstalled = Shop.where(shopify_domain: domains).pluck(:shopify_domain).to_set

      seen = {}
      scope.filter_map do |record|
        domain = record.shop_domain
        next if domain.blank? || seen[domain] || reinstalled.include?(domain)

        seen[domain] = true
        churned_candidate(record)
      end
    end

    private

    def paid_shop_scope(scope)
      scope.where("charge_id IS NOT NULL OR plan_id IN (?)", @paid_plan_ids.presence || [-1])
    end

    def new_install_candidate(shop)
      return nil if shop.shopify_domain.blank? || shop.created_at.blank?

      days = (@today - shop.created_at.to_date).to_i
      activated = @shop_cols.include?("first_order_at") ? shop.first_order_at.present? : true
      plan_value = @price_by_id[shop.plan_id].to_f
      orders = shop.try(:max_orders).to_i
      customers = shop.customer_count.to_i
      age = age_days(shop.shop_created_date)

      value = PriorityScorer.value_score(plan_value: plan_value, order_count: orders, customer_count: customers, age_days: age)
      urgency = PriorityScorer.urgency_score("new_install", days_since_install: days, activated: activated)

      reasons = ["Installed #{days}d ago", activated ? "Activated" : "Not activated yet"]
      reasons << plan_reason(plan_value, shop.plan_id)
      reasons << "#{customers} customers" if customers.positive?

      candidate(shop.shopify_domain, shop.id, "new_install", value, urgency, reasons, phone: shop.owner_phone,
                plan_value: plan_value, orders: orders, customers: customers, age_days: age)
    end

    def active_candidate(shop)
      return nil if shop.shopify_domain.blank?

      plan_value = @price_by_id[shop.plan_id].to_f
      orders = shop.try(:max_orders).to_i
      customers = shop.customer_count.to_i
      age = age_days(shop.shop_created_date)
      band = @shop_cols.include?("churn_risk_band") ? shop.churn_risk_band : nil

      value = PriorityScorer.value_score(plan_value: plan_value, order_count: orders, customer_count: customers, age_days: age)
      urgency = band.present? ? PriorityScorer.urgency_score("active", churn_band: band) : fallback_active_urgency(shop)

      reasons = []
      reasons << plan_reason(plan_value, shop.plan_id)
      reasons << "#{orders} orders" if orders.positive?
      reasons << "#{customers} customers" if customers.positive?
      reasons << "Risk: #{band}" if band.present?

      candidate(shop.shopify_domain, shop.id, "active", value, urgency, reasons, phone: shop.owner_phone,
                plan_value: plan_value, orders: orders, customers: customers, age_days: age)
    end

    def churned_candidate(record)
      days = (@today - record.created_at.to_date).to_i
      plan_name = record.try(:plan_name_at_uninstall)
      plan_value = @price_by_name[plan_name.to_s.downcase].to_f
      orders = record.order_count.to_i
      customers = record.customer_count.to_i
      age = age_days(churn_age_source(record))

      value = PriorityScorer.value_score(plan_value: plan_value, order_count: orders, customer_count: customers, age_days: age)
      urgency = PriorityScorer.urgency_score("churned", days_since_uninstall: days)

      reasons = ["Uninstalled #{days}d ago"]
      reasons << "Plan: #{plan_name}" if plan_name.present?
      reasons << "#{orders} orders" if orders.positive?
      reasons << "#{customers} customers" if customers.positive?

      candidate(record.shop_domain, record.shop_id, "churned", value, urgency, reasons, phone: record.phone,
                plan_value: plan_value, orders: orders, customers: customers, age_days: age)
    end

    def candidate(domain, shop_id, segment, value, urgency, reasons, phone:, plan_value:, orders:, customers:, age_days:)
      {
        domain: domain,
        shop_id: shop_id,
        segment: segment,
        value: value,
        urgency: urgency,
        cps: PriorityScorer.cps(value: value, urgency: urgency),
        reasons: reasons.compact,
        phone: phone,
        plan_value: plan_value,
        orders: orders,
        customers: customers,
        age_days: age_days
      }
    end

    def fallback_active_urgency(shop)
      return 30 unless @shop_cols.include?("last_order_at") && shop.last_order_at

      days = (@today - shop.last_order_at.to_date).to_i
      if days >= 30 then 100
      elsif days >= 14 then 60
      else 30
      end
    end

    def churn_age_source(record)
      if @uninstalled_cols.include?("shopify_created_on") && record.shopify_created_on.present?
        record.shopify_created_on
      else
        record.try(:shopify_created_date)
      end
    end

    def plan_reason(plan_value, plan_id)
      name = @plans.find { |p| p.id == plan_id }&.name
      if name.present?
        "Plan: #{name}"
      elsif plan_value.positive?
        "Paid plan"
      else
        "Plan: unknown"
      end
    end

    def age_days(raw)
      return 0 if raw.blank?

      date = Date.parse(raw.to_s) rescue nil
      return 0 unless date

      [(@today - date).to_i, 0].max
    end
  end
end
