class CreateLeadCollections < ActiveRecord::Migration[7.0]
  def change
    create_table :lead_collections do |t|
      t.string :email, null: false
      t.string :phone_number, null: false
      t.string :preferred_time_to_connect, null: false
      t.string :website

      t.timestamps
    end

    add_index :lead_collections, :email
    add_index :lead_collections, :created_at
  end
end
