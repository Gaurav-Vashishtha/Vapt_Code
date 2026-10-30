# frozen_string_literal: true

module CodForm
  # cod_form_rejections (ARCHITECTURE.md B.9, FRD-6). Append-only; no updated_at.
  # subject_masked must already be masked by the caller (e.g. "+36•••••4521").
  class Rejection < ApplicationRecord
    self.table_name = "cod_form_rejections"
    self.filter_attributes = filter_attributes + %i[ip]

    STAGES = %w[session quote order otp].freeze
    SUBJECT_KINDS = %w[phone email ip postal product bot].freeze

    belongs_to :shop

    validates :reason_code, presence: true
    validates :stage, presence: true, inclusion: { in: STAGES }
    validates :subject_kind, inclusion: { in: SUBJECT_KINDS }, allow_nil: true
    validate :detail_shape

    scope :recent, -> { order(created_at: :desc, id: :desc) }
    scope :since, ->(time) { where("cod_form_rejections.created_at >= ?", time) }

    private

    def detail_shape
      errors.add(:detail, "must be a JSON object") unless detail.is_a?(Hash)
    end
  end
end
