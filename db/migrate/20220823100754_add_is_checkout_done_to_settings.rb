class AddIsCheckoutDoneToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :is_checkout_done, :boolean
  end
end
