class AddBrandLogoUrlToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :brand_logo_url, :string, default:''
  end
end
