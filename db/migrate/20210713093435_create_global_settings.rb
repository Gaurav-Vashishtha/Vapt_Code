class CreateGlobalSettings < ActiveRecord::Migration[6.0]
  def change
    create_table :global_settings do |t|
      t.text :cod_include_tags
      t.text :cod_exclude_tags

      t.timestamps
    end
  end
end
