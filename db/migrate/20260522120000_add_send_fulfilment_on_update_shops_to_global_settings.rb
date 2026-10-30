class AddSendFulfilmentOnUpdateShopsToGlobalSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :global_settings, :send_fulfilment_on_update_shops, :text
  end
end
