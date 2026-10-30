require 'money/bank/open_exchange_rates_bank'

module ExchangeRateBank
  FRESH_KEY = 'exchange_rates:oxr:fresh'.freeze
  LAST_GOOD_KEY = 'exchange_rates:oxr:last_good'.freeze
  FRESH_TTL = 3.hours
  FALLBACK_USD_RATES = {
    'INR' => 1.0 / 95,
    'AED' => 0.27,
    'EGP' => 0.02
  }.freeze

  module_function

  def install!
    bank, source = resolve
    Money.default_bank = bank
    source
  end

  def fallback_usd_rate(currency)
    FALLBACK_USD_RATES[currency.to_s.upcase]
  end

  def resolve
    bank = live_bank
    return [bank, :live] if bank

    bank = last_good_bank
    return [bank, :last_good] if bank

    [static_bank, :static]
  end

  def live_bank
    bank = Money::Bank::OpenExchangeRatesBank.new
    bank.app_id = ENV['OPEN_EXCHANGE_RATES_APP_ID']
    bank.cache = proc do |text|
      if text
        Rails.cache.write(FRESH_KEY, text, expires_in: FRESH_TTL)
        Rails.cache.write(LAST_GOOD_KEY, text)
      else
        Rails.cache.read(FRESH_KEY)
      end
    end
    bank.update_rates
    bank
  rescue StandardError => e
    Rails.logger.error("[ExchangeRateBank] live rates unavailable: #{e.class}: #{e.message}")
    nil
  end

  def last_good_bank
    text = Rails.cache.read(LAST_GOOD_KEY)
    return nil if text.blank?

    bank = Money::Bank::OpenExchangeRatesBank.new
    bank.cache = proc { |incoming| incoming ? nil : text }
    bank.update_rates
    bank
  rescue StandardError => e
    Rails.logger.error("[ExchangeRateBank] last good rates unusable: #{e.class}: #{e.message}")
    nil
  end

  def static_bank
    bank = Money::Bank::VariableExchange.new
    FALLBACK_USD_RATES.each { |currency, rate| bank.add_rate(currency, 'USD', rate) }
    bank
  end
end
