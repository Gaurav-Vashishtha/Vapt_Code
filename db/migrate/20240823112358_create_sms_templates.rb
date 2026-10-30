class CreateSmsTemplates < ActiveRecord::Migration[6.0]
  def change
    create_table :sms_templates do |t|
      t.string :template_name
      t.string :message_type
      t.string :sender_id
      t.string :country_codes
      t.string :template_body
      t.string :template_example
      t.string :dlt_template_id
      t.string :status
      t.references :shop, null: false, foreign_key: true
      t.timestamps
    end
  end
end
