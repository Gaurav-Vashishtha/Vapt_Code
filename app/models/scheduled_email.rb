# frozen_string_literal: true

class ScheduledEmail < ApplicationRecord
  belongs_to :email_rule
  belongs_to :shop, optional: true
  belongs_to :uninstalled_shop, optional: true
  has_many :email_click_redirects, dependent: :destroy

  enum :status, { pending: "pending", sent: "sent", skipped: "skipped", failed: "failed", rescheduled: "rescheduled" }, validate: true

  validates :email_rule_id, uniqueness: { scope: :shop_id, message: "already has a scheduled/sent email for this shop" }, if: :shop_id?
  validates :email_rule_id, uniqueness: { scope: :uninstalled_shop_id, message: "already has a scheduled/sent email for this uninstalled shop" }, if: :uninstalled_shop_id?
  validate :shop_or_uninstalled_shop_present

  def recipient_email
    if shop_id?
      shop&.owner_email.presence || shop&.customer_email
    else
      uninstalled_shop&.email
    end
  end

  def recipient_record
    shop_id? ? shop : uninstalled_shop
  end

  def recipient_label
    shop_id? ? shop&.shopify_domain : uninstalled_shop&.shop_domain
  end

  # IANA timezone name for the recipient (for displaying scheduled_at/sent_at in shop local time). Default IST.
  def recipient_time_zone_name
    name = if shop_id? && shop&.owner_timezone.present?
             shop.owner_timezone.to_s.split(")").last.to_s.strip.presence || "Asia/Kolkata"
           else
             "Asia/Kolkata"
           end
    # Ensure the name is valid for in_time_zone (avoids view crash)
    Time.current.in_time_zone(name) && name
  rescue
    "Asia/Kolkata"
  end

  private

  def shop_or_uninstalled_shop_present
    return if shop_id.present? || uninstalled_shop_id.present?
    errors.add(:base, "Either shop or uninstalled_shop must be set")
  end
end
