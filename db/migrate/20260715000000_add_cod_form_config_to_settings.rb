class AddCodFormConfigToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :cod_form_config, :jsonb, default: {}, null: false
  end
end
