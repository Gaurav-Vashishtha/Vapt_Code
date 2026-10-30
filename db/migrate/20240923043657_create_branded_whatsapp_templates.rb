class CreateBrandedWhatsappTemplates < ActiveRecord::Migration[6.0]
  def change
    create_table :branded_whatsapp_templates do |t|
      t.string :template_name
      t.string :language
      t.string :template_type
      t.string :variables
      
      t.timestamps
      t.references :shop, foreign_key: true
    end
  end
end
