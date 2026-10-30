# frozen_string_literal: true

require "json"

module CodForm
  # Merchant-side audit trail (DSH-14, B.16): writes to the existing `settings_change_audits`
  # table with `field` prefixed `cod_form.` and `changed_by: "merchant"`.
  #
  #   CodForm::MerchantAudit.record(shop, "storefront_mode", "legacy", "cod_form")
  #   CodForm::MerchantAudit.record_changes(shop, "general", old_hash, new_hash)
  #
  # Never pass buyer data (block-list values, phones, emails): callers audit counts, not values.
  # Values of fields whose name looks like a secret are replaced by "[changed]".
  class MerchantAudit
    PREFIX = "cod_form."
    MAX_VALUE = 250
    MAX_ROWS = 60
    SECRET = /(token|secret|api_key|password|credential)/i.freeze
    CHANGED_BY = "merchant"

    class << self
      # K.9 contract: (shop, field, old_value, new_value). Never raises.
      def record(shop, field, old_value, new_value)
        return nil if old_value == new_value

        insert(shop, [row(shop, field, old_value, new_value)])
      end

      # One row per changed leaf of two hashes (dotted paths under `prefix`).
      def record_changes(shop, prefix, old_hash, new_hash)
        rows = diff(prefix, old_hash, new_hash).first(MAX_ROWS).map { |field, old, new| row(shop, field, old, new) }
        insert(shop, rows)
      end

      # Pure: [[field, old, new], ...] for every leaf that differs. Arrays are compared whole.
      def diff(prefix, old_value, new_value)
        if old_value.is_a?(Hash) && new_value.is_a?(Hash)
          (old_value.keys | new_value.keys).flat_map do |key|
            diff([prefix, key].reject { |part| part.to_s.empty? }.join("."), old_value[key], new_value[key])
          end
        elsif old_value == new_value
          []
        else
          [[prefix.to_s, old_value, new_value]]
        end
      end

      # Pure: the stored text of a value (truncated, secrets hidden).
      def format_value(field, value)
        return "[changed]" if field.to_s.match?(SECRET) && !(value.nil? || value == "")

        text = case value
               when nil then ""
               when String then value
               when Hash, Array then JSON.generate(value)
               else value.to_s
               end
        text.length > MAX_VALUE ? "#{text[0, MAX_VALUE - 1]}…" : text
      end

      def field_name(field)
        name = field.to_s
        name.start_with?(PREFIX) ? name : "#{PREFIX}#{name}"
      end

      private

      def row(shop, field, old_value, new_value)
        now = Time.current
        name = field_name(field)
        { shop_id: shop.id, field: name, old_value: format_value(name, old_value),
          new_value: format_value(name, new_value), changed_at: now, changed_by: CHANGED_BY,
          created_at: now, updated_at: now }
      end

      def insert(shop, rows)
        return nil if rows.empty?

        SettingsChangeAudit.insert_all(rows)
        rows.size
      rescue StandardError => e
        Rails.logger.warn("[CodForm::MerchantAudit] shop_id=#{shop&.id} #{e.class}")
        nil
      end
    end
  end
end
