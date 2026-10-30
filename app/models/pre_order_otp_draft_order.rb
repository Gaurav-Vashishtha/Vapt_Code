# frozen_string_literal: true

# One Shopify draft order per abandoned pre-order OTP cart session (shop_id + device_id).
# Created/updated by PreOrderOtpDraftJobs::SyncJob, removed by PreOrderOtpDraftJobs::CleanupJob
# when the shopper places an order.
#
# status:
#   pending   row reserved, draft not created yet
#   created   draft open in Shopify
#   updated   draft open in Shopify, line items replaced after the cart changed
#   failed    last Shopify call failed (last_error); retried on the next abandonment
#   converted shopper ordered; the open draft was deleted
#   deleted   draft was already gone in Shopify when we tried to clean it up
#   completed merchant completed this draft into an order
class PreOrderOtpDraftOrder < ApplicationRecord
  OPEN_STATUSES = %w[created updated].freeze
  VERIFIED_OTP_STATUSES = %w[OTP-Verified VERIFIED].freeze
  TAG = "codking-otp-abandoned"
  # Custom attribute on the draft; Shopify copies it to note_attributes when the draft is completed.
  DRAFT_ATTRIBUTE = "_codkAbandonedDraft"
  # A shopper on a second device/browser reuses the open draft from their first one within this window.
  PHONE_REUSE_WINDOW = 24.hours

  belongs_to :shop

  scope :open_drafts, -> { where(status: OPEN_STATUSES).where.not(draft_order_gid: nil) }

  def self.digits(phone)
    phone.to_s.gsub(/\D/, "").presence
  end

  def open_draft?
    OPEN_STATUSES.include?(status) && draft_order_gid.present?
  end
end
