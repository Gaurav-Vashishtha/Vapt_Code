# frozen_string_literal: true

class AddIncludeShippingInPaymentOptionsToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :include_shipping_in_payment_options, :boolean, default: false, null: false
  end
end
