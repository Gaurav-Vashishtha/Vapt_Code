class CreateTwilioLogs < ActiveRecord::Migration[6.0]
  def change
    create_table :twilio_logs do |t|
      t.string :sid
      t.string :ver_type
      t.string :country_code
      t.string :customer_number
      t.boolean :is_charged, default: false
      t.string :status
      t.references :order_confirmation, null: false, foreign_key: true
      t.references :shop, null: false, foreign_key: true

      t.timestamps
    end
  end
end
