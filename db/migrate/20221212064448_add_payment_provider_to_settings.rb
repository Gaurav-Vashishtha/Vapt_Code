class AddPaymentProviderToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :payment_provider, :string
    add_column :settings, :payment_provider_api_key, :string
    add_column :settings, :payment_provider_api_secret, :string
  end
end
