# frozen_string_literal: true

class ReopenRescheduledCallDemos < ActiveRecord::Migration[7.2]
  def up
    execute <<~SQL
      UPDATE call_demos SET status = 'scheduled', updated_at = NOW() WHERE status = 'rescheduled'
    SQL
  end

  def down; end
end
