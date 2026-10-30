class RenameRedirectIdToShopifyRedirectId < ActiveRecord::Migration[6.0]
  def change
  	rename_column :redirects, :redirect_id, :shopify_redirect_id
  end
end
