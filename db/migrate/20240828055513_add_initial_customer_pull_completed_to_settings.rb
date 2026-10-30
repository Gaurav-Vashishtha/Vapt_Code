class AddInitialCustomerPullCompletedToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :shops, :initial_customer_pull_completed, :datetime
  end
end
