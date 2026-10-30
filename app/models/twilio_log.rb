class TwilioLog < ApplicationRecord
  belongs_to :order_confirmation
  belongs_to :shop
  after_create :update_wallet_balance

  private

  def update_wallet_balance
    NetworkServices::FreeWalletService.new(shop,self.country_code, ver_type.upcase).call
  end
end