class AddCallbackFieldsToSettings < ActiveRecord::Migration[7.0]
  def change
    add_column :settings, :last_callback_request_at, :datetime
    add_column :settings, :callback_requests_count, :integer, default: 0
  end
end