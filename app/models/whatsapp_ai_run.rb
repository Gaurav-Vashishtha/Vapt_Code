# frozen_string_literal: true

class WhatsappAiRun < ApplicationRecord
  MODES = %w[auto draft suggest playground test].freeze
  OUTCOMES = %w[replied drafted handoff skipped failed].freeze

  belongs_to :shop
  belongs_to :whatsapp_conversation, optional: true

  validates :mode, inclusion: { in: MODES }
  validates :outcome, inclusion: { in: OUTCOMES }

  def as_api_json(conversation = nil)
    {
      'id' => id,
      'mode' => mode,
      'outcome' => outcome,
      'intent' => intent,
      'reply_text' => reply_text,
      'handoff_reason' => handoff_reason,
      'actions' => Array(actions),
      'credits_charged' => credits_charged,
      'conversation_id' => whatsapp_conversation_id,
      'customer' => conversation && {
        'name' => conversation.customer_name.presence,
        'phone_display' => Whatsapp::Inbox::ConversationSerializer.phone_display(conversation.customer_wa_id)
      },
      'error' => outcome == 'failed' ? error.to_s.truncate(200) : nil,
      'created_at' => created_at
    }
  end
end
