class AddThankyouMessageToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :thankyou_message, :string
  end
end
