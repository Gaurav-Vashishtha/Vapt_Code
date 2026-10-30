# frozen_string_literal: true

module CodForm
  # cod_form_admin_audits (ARCHITECTURE.md B.16, CAP-5). Append-only; no updated_at.
  class AdminAudit < ApplicationRecord
    self.table_name = "cod_form_admin_audits"

    ACTIONS = %w[create update destroy].freeze

    validates :auditable_type, presence: true
    validates :action, presence: true, inclusion: { in: ACTIONS }

    scope :recent, -> { order(created_at: :desc, id: :desc) }
    scope :for_record, ->(record) { where(auditable_type: record.class.name, auditable_id: record.id) }

    def readonly?
      persisted?
    end
  end
end
