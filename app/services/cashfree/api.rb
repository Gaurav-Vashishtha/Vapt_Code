module Cashfree
  module Api
    module_function

    # API version pinned to the Payment Links contract this integration was
    # built against. Cashfree keeps old versions working; bump deliberately.
    API_VERSION = '2022-09-01'.freeze

    def mode
      ENV.fetch('CASHFREE_MODE', Rails.env.production? ? 'prod' : 'test')
    end

    def prod?
      mode.to_s.downcase == 'prod'
    end

    # Payment Gateway base. Payment Links live under "#{pg_base}/links".
    def pg_base
      prod? ? 'https://api.cashfree.com/pg' : 'https://sandbox.cashfree.com/pg'
    end
  end
end
