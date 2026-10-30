module Payu
  module Api
    module_function

    def mode
      ENV.fetch('PAYU_MODE', Rails.env.production? ? 'prod' : 'test')
    end

    def prod?
      mode.to_s.downcase == 'prod'
    end

    def oneapi_base
      prod? ? 'https://oneapi.payu.in' : 'https://uatoneapi.payu.in'
    end

    def accounts_base
      prod? ? 'https://accounts.payu.in' : 'https://uat-accounts.payu.in'
    end

    def postservice_url
      prod? ? 'https://info.payu.in/merchant/postservice.php?form=2' : 'https://test.payu.in/merchant/postservice?form=2'
    end
  end
end
