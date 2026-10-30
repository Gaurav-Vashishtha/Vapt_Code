class CreatePreOrderOtp < ActiveRecord::Migration[6.0]
  def change
    create_table :pre_order_otps do |t|
      t.string :ip_address
      t.string :phone
      t.boolean :status
      t.string :notes
      t.string :sid
      t.string :country_code
      t.string :device_id
      t.boolean :is_charged

      t.references :shop, foreign_key: true
      t.timestamps
    end
  end
end