# frozen_string_literal: true

class CustomerIdentity < ApplicationRecord
  has_one :global_customer_stat, dependent: :destroy

  # Phone is the primary cross-shop identity key.
  validates :phone_normalized, uniqueness: true, allow_nil: true

  def self.find_or_create_by_identifiers!(phone:, email:)
    pn = RtoOrder.normalize_phone(phone)
    en = RtoOrder.normalize_email(email)

    # If phone exists, always key by phone (single identity per phone).
    if pn.present?
      ident = find_or_create_by!(phone_normalized: pn)
      # Keep latest known email for debugging/secondary matching (not unique).
      ident.update!(email_normalized: en) if en.present? && ident.email_normalized != en
      return ident
    end

    # If no phone, fall back to email-only identity.
    return find_or_create_by!(email_normalized: en) if en.present?

    raise ArgumentError, "phone or email required for identity"
  end
end

