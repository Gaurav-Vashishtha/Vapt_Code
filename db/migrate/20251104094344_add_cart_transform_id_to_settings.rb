class AddCartTransformIdToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :cart_transform_id, :string
  end
end

