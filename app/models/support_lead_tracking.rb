# frozen_string_literal: true

# One row per shop for the support dashboard "mature shop / recent install" queue.
# assigned_engineer is set from ENV["SUPPORT_ENGINEERS"] (comma-separated) using shop_id % pool.size.
class SupportLeadTracking < ApplicationRecord
  belongs_to :shop

  scope :lead_open, -> { where(closed_at: nil) }
  scope :lead_closed, -> { where.not(closed_at: nil) }

  def lead_closed?
    self.class.column_names.include?("closed_at") && read_attribute(:closed_at).present?
  end

  def self.engineer_pool
    ENV.fetch("SUPPORT_ENGINEERS", "").split(",").map(&:strip).reject(&:blank?)
  end

  def self.assign_engineer_for_shop(shop_id)
    pool = engineer_pool
    return nil if pool.empty?

    pool[shop_id % pool.size]
  end

  # Fills assigned_engineer when SUPPORT_ENGINEERS was added later or rows were created with a blank engineer.
  def self.backfill_assigned_engineers!(shop_ids)
    pool = engineer_pool
    return if pool.empty? || shop_ids.blank?

    where(shop_id: shop_ids.uniq).where(assigned_engineer: [nil, ""]).find_each do |rec|
      name = assign_engineer_for_shop(rec.shop_id)
      next if name.blank?

      rec.update_columns(assigned_engineer: name, updated_at: Time.current)
    end
  end

  # Creates rows for shop_ids that do not yet have tracking (idempotent).
  def self.assign_for_shops!(shop_ids)
    ids = shop_ids.uniq
    return if ids.blank?

    existing = where(shop_id: ids).pluck(:shop_id)
    missing = ids - existing
    return if missing.empty?

    pool = engineer_pool
    now = Time.current
    rows = missing.map do |sid|
      {
        shop_id: sid,
        assigned_engineer: pool.empty? ? nil : assign_engineer_for_shop(sid),
        activated: false,
        verified_setup: false,
        contacted: false,
        reminder_1_sent: false,
        reminder_2_sent: false,
        reminder_3_sent: false,
        not_interested: false,
        onboarded_to_free_plan: false,
        onboarded_to_paid_plan: false,
        comment: nil,
        closed_at: nil,
        created_at: now,
        updated_at: now
      }
    end
    insert_all(rows)
  end
end
