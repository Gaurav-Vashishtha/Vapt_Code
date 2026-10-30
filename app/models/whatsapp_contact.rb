class WhatsappContact < ApplicationRecord
  belongs_to :shop

  SOURCES = %w[manual csv shopify_customer abandoned_cart].freeze

  validates :phone, presence: true, uniqueness: { scope: :shop_id }
  validates :source, inclusion: { in: SOURCES }

  scope :subscribed, -> { where(subscribed: true) }

  def self.normalize_phone(raw)
    digits = RtoOrder.normalize_phone(raw).to_s.gsub(/\D/, '')
    digits.length >= 8 ? digits : nil
  rescue StandardError
    nil
  end

  def self.sanitize_tags(raw)
    Array(raw).map { |t| t.to_s.strip.downcase }.reject(&:blank?).uniq.first(50)
  end

  def self.tag_counts(shop_id, limit: 100)
    where(shop_id: shop_id)
      .joins('CROSS JOIN LATERAL jsonb_array_elements_text(tags) AS tag')
      .group('tag')
      .order(Arel.sql('count(*) DESC'))
      .limit(limit)
      .count
  end

  def self.attr_keys(shop_id, limit: 50)
    connection.select_values(sanitize_sql_array([<<~SQL.squish, shop_id, limit]))
      SELECT DISTINCT k FROM (
        SELECT jsonb_object_keys(attrs) AS k
        FROM whatsapp_contacts
        WHERE shop_id = ? AND attrs <> '{}'::jsonb
        LIMIT 5000
      ) keys ORDER BY k LIMIT ?
    SQL
  end

  # Sync/import upsert that never downgrades data a merchant already has:
  # blank incoming values lose to existing ones, counters only move up, and
  # tags/attrs merge instead of replacing. `source` and `subscribed` are
  # intentionally left untouched on conflict — first source wins, and opt-out
  # state is owned by whatsapp_opt_outs.
  MERGE_SQL = <<~SQL.squish.freeze
    name = COALESCE(NULLIF(excluded.name, ''), whatsapp_contacts.name),
    first_name = COALESCE(NULLIF(excluded.first_name, ''), whatsapp_contacts.first_name),
    last_name = COALESCE(NULLIF(excluded.last_name, ''), whatsapp_contacts.last_name),
    email = COALESCE(NULLIF(excluded.email, ''), whatsapp_contacts.email),
    source_ref = COALESCE(NULLIF(excluded.source_ref, ''), whatsapp_contacts.source_ref),
    order_count = GREATEST(COALESCE(whatsapp_contacts.order_count, 0), COALESCE(excluded.order_count, 0)),
    total_spent = GREATEST(COALESCE(whatsapp_contacts.total_spent, 0), COALESCE(excluded.total_spent, 0)),
    last_order_at = GREATEST(COALESCE(whatsapp_contacts.last_order_at, excluded.last_order_at), COALESCE(excluded.last_order_at, whatsapp_contacts.last_order_at)),
    tags = COALESCE((SELECT jsonb_agg(DISTINCT tag) FROM jsonb_array_elements(whatsapp_contacts.tags || excluded.tags) AS tag), '[]'::jsonb),
    attrs = whatsapp_contacts.attrs || excluded.attrs,
    updated_at = excluded.updated_at
  SQL

  def self.merge_rows!(rows)
    return 0 if rows.empty?
    deduped = coalesce_duplicates(rows)
    upsert_all(deduped, unique_by: %i[shop_id phone], on_duplicate: Arel.sql(MERGE_SQL))
    deduped.size
  end

  # Postgres rejects an INSERT … ON CONFLICT DO UPDATE that hits the same
  # (shop_id, phone) twice in ONE statement ("cannot affect row a second
  # time") — and one batch routinely does: a customer with several abandoned
  # carts, or a CSV listing a number twice. Fold duplicates in Ruby first,
  # using the same never-downgrade rules as MERGE_SQL.
  #
  # upsert_all also insists every row has the SAME key set, so the merge must
  # never add a key a row didn't already carry, and the result is normalised
  # to the union of keys seen (missing → nil).
  def self.coalesce_duplicates(rows)
    rows = rows.map(&:symbolize_keys)
    keys = rows.flat_map(&:keys).uniq

    merged = rows.each_with_object({}) do |r, acc|
      key = [r[:shop_id], r[:phone]]
      cur = acc[key]
      if cur.nil?
        acc[key] = r.dup
        next
      end
      %i[name first_name last_name email source_ref].each do |k|
        cur[k] = r[k] if cur[k].blank? && r[k].present?
      end
      cur[:order_count] = [cur[:order_count].to_i, r[:order_count].to_i].max if r.key?(:order_count) || cur.key?(:order_count)
      cur[:total_spent] = [cur[:total_spent].to_f, r[:total_spent].to_f].max if r.key?(:total_spent) || cur.key?(:total_spent)
      if r.key?(:last_order_at) || cur.key?(:last_order_at)
        cur[:last_order_at] = [cur[:last_order_at], r[:last_order_at]].compact.max
      end
      cur[:tags]  = (Array(cur[:tags]) + Array(r[:tags])).uniq if r.key?(:tags) || cur.key?(:tags)
      cur[:attrs] = Hash(cur[:attrs]).merge(Hash(r[:attrs])) if r.key?(:attrs) || cur.key?(:attrs)
    end

    merged.values.map { |r| keys.index_with { |k| r[k] } }
  end

  def display_name
    name.presence || [first_name, last_name].compact_blank.join(' ').presence
  end
end
