class AddFeaturedImageToAbandonedCarts < ActiveRecord::Migration[7.2]
  def change
    add_column :abandoned_carts, :featured_image, :string, default:''
  end
end
