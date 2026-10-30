# app/models/concerns/currency_helper.rb
module CurrencyHelper
    # Load currency symbols from JSON file
    CURRENCY_SYMBOLS = JSON.parse(
      File.read(Rails.root.join('app', 'javascript', 'packs', 'Components', 'currency_codes.json'))
    ).freeze
  
    # Get currency symbol for a given currency code
    def self.symbol_for(currency_code)
      CURRENCY_SYMBOLS[currency_code&.upcase] || '¤'
    end
  
    # Format amount with currency symbol
    def self.format_amount(amount, currency_code)
      symbol = symbol_for(currency_code)
      "#{symbol}#{amount}"
    end
  
    # Get all available currencies
    def self.all_currencies
      CURRENCY_SYMBOLS
    end
  
    # Get currency options for select dropdowns
    def self.currency_options
      CURRENCY_SYMBOLS.map { |code, symbol| [code, "#{code} (#{symbol})"] }.sort
    end
  
    # Check if currency code exists
    def self.valid_currency?(currency_code)
      CURRENCY_SYMBOLS.key?(currency_code&.upcase)
    end
  
    # Get currencies by symbol (useful for finding all $ currencies)
    def self.currencies_by_symbol(symbol)
      CURRENCY_SYMBOLS.select { |_code, curr_symbol| curr_symbol == symbol }.keys
    end
  end