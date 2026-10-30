class AddReviewedToShops < ActiveRecord::Migration[6.0]
  def change
    add_column :shops, :reviewed, :boolean
  end
end
