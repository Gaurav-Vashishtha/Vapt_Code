# frozen_string_literal: true

class WhatsappAiCreditTransaction < ApplicationRecord
  KINDS = %w[grant purchase auto_recharge usage refund adjust].freeze
  STATUSES = %w[pending processing completed declined failed].freeze

  belongs_to :shop

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: 'pending') }
  scope :purchases, -> { where(kind: %w[grant purchase auto_recharge adjust]) }

  def as_api_json
    {
      'id' => id,
      'kind' => kind,
      'status' => status,
      'credits' => credits,
      'balance_after' => balance_after,
      'pack' => pack,
      'amount_usd' => amount_usd&.to_s('F'),
      'note' => note,
      'created_at' => created_at
    }
  end
end
