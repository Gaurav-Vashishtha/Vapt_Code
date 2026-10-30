class AddWebUxVersionToSettings < ActiveRecord::Migration[7.0]
  def change
    add_column :settings, :web_ux_version, :integer, default: 1
  end
end

