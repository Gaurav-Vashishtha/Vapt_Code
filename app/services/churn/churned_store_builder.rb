# frozen_string_literal: true

module Churn
  # Turns a Churn::ChurnDetector::Candidate + the store's Partner revenue into
  # churned_stores attributes: profile, LTV split, and "came back" metrics.
  #
  # Uninstalled stores: the shops row (and its order_confirmations) is gone, so
  # the profile comes from the uninstalled_shops snapshot; money comes from the
  # Partner API by domain. Subscription churn: the store is still installed, so
  # the profile comes from the live shop.
  class ChurnedStoreBuilder
    TEST_ORDER_STATUS = 'Test-Order'
    TRAILING_WINDOW = 30.days

    def initialize(candidate, revenue:)
      @c = candidate
      @revenue = revenue
      @domain = candidate.domain
    end

    def attributes
      profile = @c.churn_type == 'uninstalled' ? uninstall_profile : subscription_profile
      back = @c.churn_type == 'uninstalled' ? reinstall_metrics : resubscribe_metrics

      {
        source_key: @c.source_key,
        churn_type: @c.churn_type,
        shopify_domain: @domain,
        churned_at: @c.churned_at,
        uninstalled_shop_id: @c.uninstalled_shop&.id
      }.merge(profile).merge(back).merge(revenue_metrics(back[:returned_at])).merge(
        partner_synced_at: @revenue ? Time.current : nil
      )
    end

    private

    # ---- profile -----------------------------------------------------------

    def uninstall_profile
      row = @c.uninstalled_shop
      last_plan = last_activation_before(@c.churned_at)
      unless row
        return {
          plan_name: last_plan&.charge_name,
          plan_amount: last_plan&.charge_amount,
          uninstall_reason: @c.event&.reason,
          uninstall_feedback: @c.event&.description,
          prior_churn_count: prior_uninstalls,
          features: []
        }
      end

      installed_at = parse_time(row.shopify_created_date)
      {
        owner_name: row.owner_name,
        email: row.email,
        phone: row.phone,
        country: row.country,
        store_created_on: parse_date(row.shopify_created_on),
        installed_at: installed_at,
        tenure_days: row.tenure_days || days_between(installed_at, @c.churned_at),
        orders_processed: row.order_count.to_s =~ /\A\d+\z/ ? row.order_count.to_i : nil,
        features: Churn::FeatureSet.labels_for_uninstalled(row),
        plan_name: row.plan_name_at_uninstall.presence || last_plan&.charge_name,
        plan_amount: plan_amount_for(row.plan_name_at_uninstall, last_plan),
        uninstall_reason: row.uninstall_reason.presence || @c.event&.reason,
        uninstall_feedback: row.uninstall_feedback.presence || @c.event&.description,
        prior_churn_count: prior_uninstalls
      }
    end

    def subscription_profile
      shop = live_shop
      base = {
        plan_name: @c.event&.charge_name,
        plan_amount: @c.event&.charge_amount,
        prior_churn_count: ChurnedStore.where(shopify_domain: @domain).where('churned_at < ?', @c.churned_at).count
      }
      unless shop
        # Uninstalled later: fall back to the snapshot taken at that uninstall.
        row = UninstalledShop.where(shop_domain: @domain).where('created_at > ?', @c.churned_at).order(:created_at).first
        return base.merge(features: []) unless row

        installed_at = parse_time(row.shopify_created_date)
        return base.merge(
          owner_name: row.owner_name, email: row.email, phone: row.phone, country: row.country,
          store_created_on: parse_date(row.shopify_created_on), installed_at: installed_at,
          tenure_days: days_between(installed_at, @c.churned_at),
          features: Churn::FeatureSet.labels_for_uninstalled(row)
        )
      end

      # shops.installed_at isn't in every environment's schema; created_at is the latest install.
      installed_at = (shop.has_attribute?(:installed_at) ? shop[:installed_at] : nil) || shop.created_at
      base.merge(
        shop_id: shop.id,
        owner_name: shop.owner_name.presence || shop.shop_owner,
        email: shop.owner_email.presence || shop.customer_email,
        phone: shop.owner_phone,
        country: shop.country_code,
        store_created_on: parse_date(shop.shop_created_date),
        installed_at: installed_at,
        tenure_days: days_between(installed_at, @c.churned_at),
        orders_processed: real_orders(shop).where('created_at <= ?', @c.churned_at).count,
        features: Churn::FeatureSet.labels_for_shop(shop)
      )
    end

    # ---- came back ---------------------------------------------------------

    def reinstall_metrics
      shop = live_shop
      after = @c.churned_at + ChurnDetector::SNAPSHOT_DEDUPE_WINDOW
      reinstalled_now = shop && shop.created_at > @c.churned_at

      returns = []
      returns << shop.created_at if reinstalled_now
      next_row = UninstalledShop.where(shop_domain: @domain).where('created_at > ?', after).order(:created_at).first
      if next_row
        # A later uninstall proves a reinstall; its snapshot's install date is when.
        install_date = parse_time(next_row.shopify_created_date)
        returns << (install_date && install_date > @c.churned_at ? install_date : next_row.created_at)
      end
      install_event = PartnerAppEvent.for_domain(@domain).of_type(PartnerAppEvent::INSTALLED)
                                     .where('occurred_at > ?', @c.churned_at).order(:occurred_at).first
      returns << install_event.occurred_at if install_event
      returned_at = returns.compact.min

      {
        returned: returned_at.present?,
        returned_at: returned_at,
        return_gap_days: returned_at ? days_between(@c.churned_at, returned_at) : nil,
        still_installed: reinstalled_now ? true : false,
        shop_id: reinstalled_now ? shop.id : nil,
        current_plan_name: reinstalled_now ? shop.plan&.name : nil,
        orders_since_return: reinstalled_now ? real_orders(shop).where('created_at >= ?', shop.created_at).count : nil
      }
    end

    def resubscribe_metrics
      shop = live_shop
      resub = PartnerAppEvent.for_domain(@domain).of_type(PartnerAppEvent::CHARGE_ACTIVATED).live_charges
                             .where('occurred_at > ?', @c.churned_at + ChurnDetector::PLAN_SWITCH_WINDOW)
                             .where('charge_amount > 0')
                             .order(:occurred_at).first
      returned_at = resub&.occurred_at
      {
        returned: returned_at.present?,
        returned_at: returned_at,
        return_gap_days: returned_at ? days_between(@c.churned_at, returned_at) : nil,
        still_installed: shop.present?,
        current_plan_name: shop&.plan&.name,
        orders_since_return: shop && returned_at ? real_orders(shop).where('created_at >= ?', returned_at).count : nil
      }
    end

    # ---- money -------------------------------------------------------------

    def revenue_metrics(returned_at)
      return { sync_error: 'Partner revenue unavailable' } unless @revenue

      # LTV covers the stint that ended in this churn: everything up to the
      # moment the store came back (or everything, if it never did).
      summary = @revenue.summary(until_time: returned_at)
      # A store downgraded to Free keeps paying usage, so only the subscription
      # part of its revenue is lost; uninstalls and cancellations lose it all.
      lost_type = @c.churn_type == 'downgraded_to_free' ? 'subscription' : nil
      summary.merge(
        last_30d_net: @revenue.net_between(@c.churned_at - TRAILING_WINDOW, @c.churned_at, sale_type: lost_type),
        net_since_return: returned_at ? @revenue.net_between(returned_at, nil) : 0,
        sync_error: nil
      )
    end

    # ---- helpers -----------------------------------------------------------

    def live_shop
      return @live_shop if defined?(@live_shop)

      @live_shop = Shop.real_installs.includes(:plan, :setting).find_by(shopify_domain: @domain)
    end

    def real_orders(shop)
      OrderConfirmation.where(shop_id: shop.id).where('status IS DISTINCT FROM ?', TEST_ORDER_STATUS)
    end

    # Distinct earlier uninstalls (UninstallJob + UninstallNewJob can write two
    # rows for one uninstall, so rows within the dedupe window count once).
    def prior_uninstalls
      times = UninstalledShop.where(shop_domain: @domain)
                             .where('created_at < ?', @c.churned_at - ChurnDetector::SNAPSHOT_DEDUPE_WINDOW)
                             .order(:created_at).pluck(:created_at)
      times.each_with_index.count do |t, i|
        nxt = times[i + 1]
        nxt.nil? || (nxt - t) >= ChurnDetector::SNAPSHOT_DEDUPE_WINDOW
      end
    end

    def last_activation_before(time)
      PartnerAppEvent.for_domain(@domain).of_type(PartnerAppEvent::CHARGE_ACTIVATED).live_charges
                     .where('occurred_at <= ?', time).order(occurred_at: :desc).first
    end

    def plan_amount_for(plan_name, last_activation)
      return nil unless last_activation
      return last_activation.charge_amount if plan_name.blank?

      last_activation.charge_name.to_s.casecmp?(plan_name.to_s) ? last_activation.charge_amount : nil
    end

    def days_between(from, to)
      return nil unless from && to
      ((to - from) / 1.day).floor
    end

    def parse_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def parse_date(value)
      parse_time(value)&.to_date
    end
  end
end
