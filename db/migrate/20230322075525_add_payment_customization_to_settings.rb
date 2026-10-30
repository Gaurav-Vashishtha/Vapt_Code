class AddPaymentCustomizationToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :payment_customization_id, :string
    add_column :settings, :payment_method_name, :string
    add_column :settings, :min_cart_total, :decimal
    add_column :settings, :max_cart_total, :decimal
  end
end
