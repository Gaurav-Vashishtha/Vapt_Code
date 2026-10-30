class AddIsShippingPhoneDoneToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :is_shipping_phone_done, :boolean
  end
end
