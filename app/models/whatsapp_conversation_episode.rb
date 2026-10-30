# frozen_string_literal: true

class WhatsappConversationEpisode < ApplicationRecord
  belongs_to :whatsapp_conversation
  belongs_to :shop
  belongs_to :first_response_agent, class_name: 'WhatsappInboxAgent', optional: true

  scope :unresolved, -> { where(resolved_at: nil) }

  def resolved?
    resolved_at.present?
  end
end
