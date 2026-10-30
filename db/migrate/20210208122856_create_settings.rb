class CreateSettings < ActiveRecord::Migration[6.0]
  def change
    create_table :settings do |t|
      t.boolean :status, :default => false
      t.text :template
      t.boolean :sms
      t.boolean :whatsapp
      t.boolean :ivr
      t.references :shop, foreign_key: true
    end
  end
end
