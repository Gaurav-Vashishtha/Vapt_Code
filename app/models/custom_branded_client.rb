# frozen_string_literal: true

# A partner-facing branded-WhatsApp tenant. Deliberately NOT a Shop: no
# Shopify install, no token, no Setting — it owns WhatsApp accounts (and
# through them templates/logs) directly via custom_branded_client_id, so
# nothing here ever enters shop-iterating jobs, billing, or Shopify callbacks.
#
# Mirrors Shop's WhatsApp-owner interface (whatsapp_accounts,
# default_whatsapp_account, whatsapp_templates, whatsapp_message_logs) so the
# shared controller concerns and Meta services work with either owner.
class CustomBrandedClient < ApplicationRecord
  has_many :custom_branded_template_events, dependent: :destroy
  has_many :whatsapp_accounts, dependent: :destroy
  has_many :whatsapp_templates, through: :whatsapp_accounts
  has_many :whatsapp_message_logs, dependent: :destroy
  has_many :whatsapp_inbound_messages, dependent: :destroy
  has_many :custom_branded_api_keys, dependent: :destroy

  # Conservative hostname shape: letters/digits/hyphens/dots, must contain a
  # dot. Keeps garbage and injection attempts out of the identifier column.
  DOMAIN_FORMAT = /\A[a-z0-9][a-z0-9\-]*(\.[a-z0-9][a-z0-9\-]*)+\z/

  validates :domain, presence: true, uniqueness: true,
                     length: { maximum: 255 },
                     format: { with: DOMAIN_FORMAT, message: 'must be a bare lowercase hostname' }

  def self.normalize_domain(value)
    value.to_s.strip.downcase.sub(%r{\Ahttps?://}, '').sub(%r{[/?#].*\z}, '')
  end

  # Same fallback chain as Shop#default_whatsapp_account so both owners
  # behave identically in the shared concerns and send paths.
  def default_whatsapp_account
    whatsapp_accounts.find_by(is_default: true) ||
      whatsapp_accounts.active.order(:id).first ||
      whatsapp_accounts.order(:id).first
  end

  def display_name
    label.presence || domain
  end
end
