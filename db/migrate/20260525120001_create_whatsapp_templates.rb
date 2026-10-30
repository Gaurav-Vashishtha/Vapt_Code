class CreateWhatsappTemplates < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsapp_templates do |t|
      t.references :whatsapp_account, null: false, foreign_key: true

      t.string :meta_template_id
      t.string :name, null: false
      t.string :language, null: false, default: 'en_US'
      t.string :category, null: false
      t.integer :status, null: false, default: 0

      t.jsonb :components, default: [], null: false
      t.string :rejection_reason

      t.datetime :last_synced_at

      t.timestamps
    end

    add_index :whatsapp_templates, :meta_template_id
    add_index :whatsapp_templates, [:whatsapp_account_id, :name, :language], unique: true, name: 'idx_whatsapp_templates_uniqueness'
    add_index :whatsapp_templates, :status
  end
end
