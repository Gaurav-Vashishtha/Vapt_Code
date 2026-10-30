# frozen_string_literal: true

class WhatsappConversationMessage < ApplicationRecord
  SOURCES = %w[customer agent auto_reply notification campaign payment_link system ai].freeze
  KINDS = %w[text image video audio document sticker location contacts reaction button interactive
             template order unsupported system].freeze
  MEDIA_KINDS = %w[image video audio document sticker].freeze
  STATUS_ORDER = { 'queued' => 0, 'sent' => 1, 'delivered' => 2, 'read' => 3, 'failed' => 4 }.freeze

  belongs_to :whatsapp_conversation
  belongs_to :shop
  belongs_to :whatsapp_inbound_message, optional: true
  belongs_to :whatsapp_message_log, optional: true
  belongs_to :agent, class_name: 'WhatsappInboxAgent', optional: true

  has_one_attached :media_file, service: :whatsapp_media

  enum :direction, { inbound: 0, outbound: 1 }
  enum :status, { queued: 0, sent: 1, delivered: 2, read: 3, failed: 4 }, prefix: :delivery
  enum :media_state, { none: 0, pending: 1, stored: 2, failed: 3, purged: 4 }, prefix: :media

  validates :source, inclusion: { in: SOURCES }
  validates :kind, inclusion: { in: KINDS }
  validates :occurred_at, presence: true

  def media?
    MEDIA_KINDS.include?(kind)
  end

  # Conditional UPDATE so two status webhooks processed concurrently can never
  # move a message backwards (Meta sends delivered/read out of order).
  def advance_status!(new_status, at:, error: nil)
    new_status = new_status.to_s
    rank = STATUS_ORDER[new_status]
    return false if rank.nil?

    attrs = { status: rank, updated_at: Time.current }
    attrs[:"#{new_status}_at"] = at if new_status != 'queued'
    if new_status == 'failed'
      err = error.is_a?(Hash) ? error : {}
      attrs[:error_code] = err['code'].to_s.presence
      attrs[:error_message] = (err['message'] || err['title'] || err.dig('error_data', 'details')).to_s.presence
    end

    scope = self.class.where(id: id)
    scope = scope.where('status IS NULL OR status < ?', rank) unless new_status == 'failed'
    changed = scope.update_all(attrs) == 1
    if changed
      assign_attributes(attrs.merge(status: new_status))
      clear_changes_information
    end
    changed
  end

  def self.preview_for(kind:, body: nil, content: {}, file_name: nil)
    content = content.is_a?(Hash) ? content : {}
    text = body.to_s.strip
    case kind.to_s
    when 'image' then text.presence || 'Photo'
    when 'video' then text.presence || 'Video'
    when 'audio' then content['voice'] ? 'Voice message' : 'Audio'
    when 'document' then text.presence || file_name.presence || 'Document'
    when 'sticker' then 'Sticker'
    when 'location' then ['Location', text.presence].compact.join(': ')
    when 'contacts' then ['Contact', text.presence].compact.join(': ')
    when 'reaction' then content['emoji'].present? ? "Reacted #{content['emoji']}" : 'Removed a reaction'
    when 'unsupported' then 'Unsupported message'
    else text.presence || kind.to_s.humanize
    end
  end
end
