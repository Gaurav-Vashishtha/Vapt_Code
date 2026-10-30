class SmsTemplateApproval < ApplicationRecord
  self.table_name = "sms_template_approvals"

  STATUSES = {
    pending: "pending",
    approved: "approved",
    rejected: "rejected"
  }.freeze

  belongs_to :shop
  belongs_to :setting
  belongs_to :template_type_config,
             class_name: "SmsTemplateTypeConfig",
             primary_key: :key,
             foreign_key: :template_type_key,
             optional: true,
             inverse_of: :sms_template_approvals

  validates :template_type_key, :target_column, :body, :status, :submitted_at, presence: true
  validates :status, inclusion: { in: STATUSES.values }
end
