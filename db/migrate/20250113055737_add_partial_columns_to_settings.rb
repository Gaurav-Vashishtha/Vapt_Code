class AddPartialColumnsToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :partial_payment_enabled, :boolean, default:false
  end
end
