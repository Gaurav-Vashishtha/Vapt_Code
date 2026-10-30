class AddDynamicConfigToAbandonedCarts < ActiveRecord::Migration[7.2]
  def change
    add_column :abandoned_carts, :dynamic_config, :jsonb ,  default: []
  end
end
