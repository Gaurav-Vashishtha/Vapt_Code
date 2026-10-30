# frozen_string_literal: true

class WhatsappConversationLabel < ApplicationRecord
  belongs_to :whatsapp_conversation
  belongs_to :whatsapp_inbox_label
  belongs_to :shop

  SOURCES = %w[agent auto].freeze

  validates :source, inclusion: { in: SOURCES }

  def self.add!(conversation, label_ids, source:)
    ids = Array(label_ids).map(&:to_i).uniq
    return if ids.empty?

    now = Time.current
    rows = ids.map do |label_id|
      { whatsapp_conversation_id: conversation.id, whatsapp_inbox_label_id: label_id,
        shop_id: conversation.shop_id, source: source, created_at: now }
    end
    insert_all(rows, unique_by: :idx_wa_conv_labels_unique)
  end

  def self.replace!(conversation, label_ids)
    ids = WhatsappInboxLabel.where(shop_id: conversation.shop_id, id: Array(label_ids).map(&:to_i)).pluck(:id)
    transaction do
      where(whatsapp_conversation_id: conversation.id).where.not(whatsapp_inbox_label_id: ids).delete_all
      add!(conversation, ids, source: 'agent')
    end
    labels_for(conversation)
  end

  def self.labels_for(conversation)
    WhatsappInboxLabel.where(shop_id: conversation.shop_id)
                      .where(id: where(whatsapp_conversation_id: conversation.id).select(:whatsapp_inbox_label_id))
                      .ordered
  end
end
