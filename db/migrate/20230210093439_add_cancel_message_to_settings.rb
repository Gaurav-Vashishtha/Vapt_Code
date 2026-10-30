class AddCancelMessageToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :cancel_template, :string, :default => 'Order placed on {{store_url}} is canceled. Reason - Phone number not verified. Visit {{store_url}} to place a new order.'
    add_column :settings, :cancel_notif_enabled, :boolean, :default => false
  end
end
