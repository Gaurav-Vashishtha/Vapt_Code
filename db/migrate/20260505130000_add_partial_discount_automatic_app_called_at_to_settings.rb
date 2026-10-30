class AddPartialDiscountAutomaticAppCalledAtToSettings < ActiveRecord::Migration[7.0]
  def change
    add_column :settings, :partial_discount_automatic_app_called_at, :datetime
  end
end
