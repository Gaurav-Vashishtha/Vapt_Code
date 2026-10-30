# One exit-survey submission from the uninstall email (see UninstallSurveysController).
class ExitSurveyResponse < ApplicationRecord
  belongs_to :uninstalled_shop, optional: true

  validates :shop_domain, :submitted_at, presence: true

  scope :recent_first, -> { order(submitted_at: :desc) }
  scope :in_period, ->(from, to) { where(submitted_at: from..to) }
  scope :wants_callback, -> { where(wants_callback: true) }

  def reason_label
    Churn::ExitSurvey.reason_label(reason) || 'No reason picked'
  end
end
