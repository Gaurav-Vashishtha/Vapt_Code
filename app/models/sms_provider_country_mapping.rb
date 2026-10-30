# frozen_string_literal: true

class SmsProviderCountryMapping < ApplicationRecord
  validates :provider, presence: true, uniqueness: true
  validates :supported_countries, presence: true

  # Get array of country codes for this provider
  def country_codes
    return [] if supported_countries.blank?
    supported_countries.split(',').map(&:strip).reject(&:blank?)
  end

  # Check if provider supports a specific country
  def supports_country?(country_code)
    return false if country_code.blank?
    country_codes.map(&:upcase).include?(country_code.to_s.upcase)
  end

  # Class method to find providers for a country
  def self.providers_for_country(country_code)
    return [] if country_code.blank?
    
    all.select { |mapping| mapping.supports_country?(country_code) }
  end

  # Class method to get provider service class names for a country
  def self.provider_services_for_country(country_code)
    providers_for_country(country_code).map(&:provider)
  end
end

