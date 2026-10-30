class CreateRedirects < ActiveRecord::Migration[6.0]
  def change
    create_table :redirects do |t|
      t.string :path
      t.string :target
      t.references :shop, null: false, foreign_key: true

      t.timestamps
    end
  end
end
