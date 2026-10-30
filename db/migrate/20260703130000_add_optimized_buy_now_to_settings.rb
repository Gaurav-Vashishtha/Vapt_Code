class AddOptimizedBuyNowToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :optimized_buy_now, :boolean, default: false, null: false
  end
end
