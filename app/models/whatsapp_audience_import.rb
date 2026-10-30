class WhatsappAudienceImport < ApplicationRecord
  belongs_to :shop
  has_one_attached :file
  has_many :campaigns, class_name: 'WhatsappCampaign', dependent: :nullify

  STATUSES = %w[uploaded parsing ready failed].freeze
end
