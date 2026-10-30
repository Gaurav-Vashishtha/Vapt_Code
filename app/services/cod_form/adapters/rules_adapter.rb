# frozen_string_literal: true

module CodForm
  # Setting (Limit COD columns) -> CodForm::Engine::CodRules rules hash (ARCHITECTURE.md E.3).
  # Reads the columns as stored, on every plan. Nothing here writes to Setting.
  class RulesAdapter
    # Columns whose change must re-sync the storefront metafield (C.1).
    WATCHED_COLUMNS = %w[
      selected_countries show_provinces hide_provinces selected_zips excluded_zips
      selected_product_ids show_product_ids hide_product_variant_ids
      excluded_collection_ids selected_collection_ids hide_vendors show_vendors
      min_cart_total max_cart_total phone_numbers email_addresses hide_gift_cards
    ].freeze

    class << self
      def from_setting(setting)
        return empty if setting.nil?

        {
          "allow_countries" => list(read(setting, :selected_countries)).map(&:upcase),
          "allow_provinces" => list(read(setting, :show_provinces)),
          "deny_provinces" => list(read(setting, :hide_provinces)),
          "allow_zips" => read(setting, :selected_zips).to_s,
          "deny_zips" => read(setting, :excluded_zips).to_s,
          "deny_product_ids" => ids(read(setting, :selected_product_ids)),
          "allow_product_ids" => ids(read(setting, :show_product_ids)),
          "deny_variant_ids" => ids(read(setting, :hide_product_variant_ids)),
          "allow_collection_ids" => ids(read(setting, :selected_collection_ids)),
          "deny_collection_ids" => ids(read(setting, :excluded_collection_ids)),
          "deny_vendors" => list(read(setting, :hide_vendors)).map(&:downcase),
          "allow_vendors" => list(read(setting, :show_vendors)).map(&:downcase),
          "min_total_cents" => cents(read(setting, :min_cart_total)),
          "max_total_cents" => cents(read(setting, :max_cart_total)),
          "deny_phones" => list(read(setting, :phone_numbers)).map { |v| v.gsub(/\D/, "") }.reject(&:empty?),
          "deny_emails" => list(read(setting, :email_addresses)).map(&:downcase),
          "hide_gift_cards" => read(setting, :hide_gift_cards) ? true : false
        }
      end

      def empty
        {
          "allow_countries" => [], "allow_provinces" => [], "deny_provinces" => [],
          "allow_zips" => "", "deny_zips" => "",
          "deny_product_ids" => [], "allow_product_ids" => [], "deny_variant_ids" => [],
          "allow_collection_ids" => [], "deny_collection_ids" => [],
          "deny_vendors" => [], "allow_vendors" => [],
          "min_total_cents" => nil, "max_total_cents" => nil,
          "deny_phones" => [], "deny_emails" => [], "hide_gift_cards" => false
        }
      end

      private

      def read(setting, column)
        setting.respond_to?(column) ? setting.public_send(column) : nil
      end

      def list(value)
        value.to_s.split(/[,\n;]/).map(&:strip).reject(&:empty?)
      end

      # Ids are stored as plain numbers or gids; the engines compare numeric-id strings.
      def ids(value)
        list(value).map { |entry| entry.split("/").last.to_s }.reject(&:empty?)
      end

      def cents(value)
        return nil if value.nil?

        amount = (value.to_d * 100).round.to_i
        amount.positive? ? amount : nil
      end
    end
  end
end
