class AddStrikePriceToPlans < ActiveRecord::Migration[6.0]
  def change
    add_column :plans, :strike_price, :string
    add_column :plans, :recommended, :boolean
    add_column :plans, :max_sms, :integer
  end
end
