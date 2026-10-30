class AddMoreFieldsToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :otp_wait_time, :integer
    add_column :settings, :max_retries, :integer
  end
end
