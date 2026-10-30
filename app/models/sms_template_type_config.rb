class SmsTemplateTypeConfig < ApplicationRecord
  self.table_name = "sms_template_type_configs"

  has_many :sms_template_approvals,
           primary_key: :key,
           foreign_key: :template_type_key,
           inverse_of: :template_type_config

  validates :key, :display_name, :target_column, presence: true
  validates :key, uniqueness: true
  validates :max_variables, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }
end
