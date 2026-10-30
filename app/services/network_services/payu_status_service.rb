module NetworkServices
  class PayuStatusService < ApplicationService
    attr_reader :shop, :order_confirmation

    # NetworkServices::PayuStatusService.call(Shop.last, OrderConfirmation.last)
    def initialize(shop, order_confirmation, test = false)
      @shop = shop
      @order_confirmation = order_confirmation
      @test = test
    end

    def call
      return false if order_confirmation.blank?

      credentials = Payu::Credentials.for(shop.setting)
      return false unless credentials.verify_ready?

      txnids = order_confirmation.phonepe_transaction_ids.to_s.split(',').map(&:strip).reject(&:blank?)
      return false if txnids.empty?

      var1 = txnids.join('|')
      command = 'verify_payment'
      hash = Digest::SHA512.hexdigest("#{credentials.merchant_key}|#{command}|#{var1}|#{credentials.salt}")

      resp = HTTParty.post(
        Payu::Api.postservice_url,
        body: {
          key: credentials.merchant_key,
          command: command,
          var1: var1,
          hash: hash
        },
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        timeout: 20
      )
      return false unless resp.success?

      parsed = JSON.parse(resp.body || '{}') rescue {}
      details = parsed['transaction_details']
      return false unless details.is_a?(Hash)

      details.any? { |_txnid, txn| txn.is_a?(Hash) && txn['status'].to_s.downcase == 'success' }
    rescue => e
      Rails.logger.error("[PayuStatusService] order=#{order_confirmation&.id} verify failed: #{e.class}: #{e.message}")
      false
    end
  end
end
