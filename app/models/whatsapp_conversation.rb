# frozen_string_literal: true

class WhatsappConversation < ApplicationRecord
  WINDOW = 24.hours

  belongs_to :shop
  belongs_to :whatsapp_account, optional: true
  belongs_to :assignee_agent, class_name: 'WhatsappInboxAgent', optional: true
  belongs_to :current_episode, class_name: 'WhatsappConversationEpisode', optional: true

  has_many :messages, class_name: 'WhatsappConversationMessage', inverse_of: :whatsapp_conversation
  has_many :episodes, class_name: 'WhatsappConversationEpisode', inverse_of: :whatsapp_conversation

  enum :status, { open: 0, pending: 1, resolved: 2 }
  enum :last_message_direction, { inbound: 0, outbound: 1 }, prefix: :last

  validates :customer_wa_id, :phone_last10, :status_changed_at, :last_inbound_at, :last_message_at, presence: true

  def self.phone_last10(raw)
    raw.to_s.gsub(/\D/, '').last(10)
  end

  def window_expires_at
    last_inbound_at && last_inbound_at + WINDOW
  end

  def window_open?(now = Time.current)
    return false if last_inbound_at.nil? || window_expires_at <= now

    window_closed_hint_at.nil? || window_closed_hint_at < last_inbound_at
  end

  # Moves last_message_* forward only, so an out-of-order webhook or a
  # back-filled older message never replaces a newer preview.
  def self.touch_last_message!(conversation_id, at:, preview:, direction:)
    where(id: conversation_id)
      .where('last_message_at <= ?', at)
      .update_all(
        last_message_at: at,
        last_message_preview: preview.to_s.truncate(200),
        last_message_direction: last_message_directions.fetch(direction.to_s),
        updated_at: Time.current
      )
  end
end
