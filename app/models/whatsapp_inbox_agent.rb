# frozen_string_literal: true

class WhatsappInboxAgent < ApplicationRecord
  STORE_TEAM_ID = 0

  belongs_to :shop

  validates :shopify_user_id, presence: true

  def store_team?
    shopify_user_id.to_i == STORE_TEAM_ID
  end

  def display_name
    return name if name.present?
    return I18n.t('whatsapp_inbox.store_team', default: 'Store team') if store_team?

    "Staff #{shopify_user_id}"
  end
end
