# frozen_string_literal: true

class AddClosedAtToSupportLeadTrackings < ActiveRecord::Migration[7.2]
  def change
    add_column :support_lead_trackings, :closed_at, :datetime
    add_index :support_lead_trackings, :closed_at
  end
end
