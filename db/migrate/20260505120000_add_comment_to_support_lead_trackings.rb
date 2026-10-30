# frozen_string_literal: true

class AddCommentToSupportLeadTrackings < ActiveRecord::Migration[7.2]
  def change
    add_column :support_lead_trackings, :comment, :text
  end
end

