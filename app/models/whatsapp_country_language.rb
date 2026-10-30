# frozen_string_literal: true

# Default WhatsApp language suggested during onboarding for shops in a country (set in the support
# dashboard). A country without a row, or whose language is not approved yet, falls back to English.
class WhatsappCountryLanguage < ApplicationRecord
  before_validation { self.country_code = country_code.to_s.strip.upcase }

  validates :country_code, presence: true, uniqueness: true, format: { with: /\A[A-Z]{2}\z/ }
  validates :language, inclusion: { in: WhatsappTemplateTranslation::LANGUAGES.keys }

  def self.language_for(country_code)
    code = country_code.to_s.strip.upcase
    return nil if code.empty?

    find_by(country_code: code)&.language
  end
end
