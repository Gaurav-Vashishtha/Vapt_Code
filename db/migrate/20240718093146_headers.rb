class Headers < ActiveRecord::Migration[6.0]
  def change
    create_table :headers do |t|
      t.string :header_id, default: ""
      t.string :country_codes, default: ""
      t.string :dlt_principal_entity_id, default: ""
      t.string :status,  default: "requested", null: false
      t.references :shop, foreign_key: true
      t.timestamps
    end
  end
end
