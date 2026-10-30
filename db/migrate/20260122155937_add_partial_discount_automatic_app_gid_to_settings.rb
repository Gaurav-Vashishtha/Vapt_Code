class AddPartialDiscountAutomaticAppGidToSettings < ActiveRecord::Migration[7.0]
  def change
    add_column :settings, :partial_discount_automatic_app_gid, :string
  end
end

