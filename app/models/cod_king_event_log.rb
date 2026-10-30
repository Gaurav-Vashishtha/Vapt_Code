# frozen_string_literal: true

class CodKingEventLog < ApplicationRecord
  self.table_name = "cod_king_event_logs"

  belongs_to :shop

  validates :event_type, presence: true
  validates :session_id, presence: true
  validates :metadata, presence: true
end
