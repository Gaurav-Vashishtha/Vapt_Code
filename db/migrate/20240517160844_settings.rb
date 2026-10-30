class Settings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :prepaid_banner_color, :string, default: '#FFE477'
  end
end
