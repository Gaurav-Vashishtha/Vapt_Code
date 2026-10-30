class AddRedirectIdToRedirects < ActiveRecord::Migration[6.0]
  def change
    add_column :redirects, :redirect_id, :string
  end
end
