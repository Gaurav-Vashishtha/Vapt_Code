# frozen_string_literal: true

module Api
  module Sidekick
    # What decides whether a customer sees COD and what they pay for it:
    # Limit COD rules, COD fee, partial payment rules and active discounts.
    class CodRulesController < BaseController
      LIST_PREVIEW = 10

      def show
        setting = @shop.setting

        render json: {
          results: [
            resource_link(
              type: 'cod_rules',
              id: @shop.id,
              name: "COD rules — #{@shop.shopify_domain}",
              meta: {
                limit_cod: setting && limit_cod(setting),
                cod_fee: setting && { enabled: setting.cod_fee_enabled, amount: setting.cod_fees&.to_f },
                partial_payment: {
                  enabled: setting&.partial_payment_enabled,
                  rules: partial_rules
                },
                active_discounts: discounts
              }
            )
          ]
        }
      end

      private

      def limit_cod(setting)
        {
          min_cart_total: setting.min_cart_total&.to_f,
          max_cart_total: setting.max_cart_total&.to_f,
          cod_only_for_pincodes: list(setting.selected_zips),
          cod_hidden_for_pincodes: list(setting.excluded_zips),
          cod_only_for_provinces: list(setting.show_provinces),
          cod_hidden_for_provinces: list(setting.hide_provinces),
          cod_only_for_vendors: list(setting.show_vendors),
          cod_hidden_for_vendors: list(setting.hide_vendors),
          cod_only_for_products_count: count(setting.show_product_ids),
          cod_hidden_for_variants_count: count(setting.hide_product_variant_ids),
          cod_only_for_collections_count: count(setting.selected_collection_ids),
          cod_hidden_for_collections_count: count(setting.excluded_collection_ids)
        }.compact
      end

      def partial_rules
        @shop.partial_rule_sets.where(is_enabled: true).order(:position).limit(LIST_PREVIEW).map do |rule|
          {
            name: rule.rule_name,
            advance: [rule.amount&.to_f, rule.amount_type].compact.join(' '),
            applies_to: rule.is_all ? 'all products' : rule.product_scope,
            cart_range: rule.is_cart_rule ? [rule.min_cart_range&.to_f, rule.max_cart_range&.to_f] : nil
          }.compact
        end
      end

      def discounts
        now = Time.current
        @shop.discounts.where(is_active: true)
             .where('starts_at IS NULL OR starts_at <= ?', now)
             .where('ends_at IS NULL OR ends_at >= ?', now)
             .order(:display_order).limit(LIST_PREVIEW)
             .map { |d| { title: d.title, code: d.code.presence, type: d.discount_type, value: d.value&.to_f, sync_status: d.sync_status }.compact }
      end

      def split(value)
        value.to_s.split(/[\s,]+/).reject(&:blank?)
      end

      def list(value)
        items = split(value)
        return nil if items.empty?

        items.size > LIST_PREVIEW ? { count: items.size, first: items.first(LIST_PREVIEW) } : items
      end

      def count(value)
        split(value).size.nonzero?
      end
    end
  end
end
