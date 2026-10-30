class AddAbandonedCartConfigsToSettings < ActiveRecord::Migration[7.2]
  def change
        add_column :settings, :abandoned_cart_configs, :jsonb, default: []
  end
end
