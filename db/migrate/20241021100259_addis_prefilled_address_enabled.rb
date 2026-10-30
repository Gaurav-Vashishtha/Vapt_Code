class AddisPrefilledAddressEnabled < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :is_prefilled_address_enabled, :boolean, default:false
  end
end
