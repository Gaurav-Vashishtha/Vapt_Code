class AddPreShowBrandingToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :pre_show_branding, :boolean, default:true
  end
end


    