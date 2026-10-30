# frozen_string_literal: true

class AddPrivatePaymentProviderAndCodFormEnabledToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :private_payment_provider, :jsonb, default: nil
    add_column :settings, :cod_form_enabled, :boolean, default: false, null: false
  end
end
