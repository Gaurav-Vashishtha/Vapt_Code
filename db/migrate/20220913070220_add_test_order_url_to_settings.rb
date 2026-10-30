class AddTestOrderUrlToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :test_order_url, :string
  end
end
