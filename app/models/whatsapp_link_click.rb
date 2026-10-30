# frozen_string_literal: true

class WhatsappLinkClick < ApplicationRecord
  belongs_to :shop

  validates :event_type_key, :clicked_at, presence: true
end
