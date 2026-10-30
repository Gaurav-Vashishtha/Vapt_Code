class AddTimestampsToTwilioPricings < ActiveRecord::Migration[6.0]
  def change
    add_column :twilio_pricings, :created_at, :timestamp
    add_column :twilio_pricings, :updated_at, :timestamp
  end
end
