# frozen_string_literal: true

class AddCustomerCountToShops < ActiveRecord::Migration[7.0]
  def change
    add_column :shops, :customer_count, :integer
  end
end
