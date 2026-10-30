class AddNumSegmentToTwilioLogs < ActiveRecord::Migration[6.0]
  def change
    add_column :twilio_logs, :num_segment, :integer
  end
end
