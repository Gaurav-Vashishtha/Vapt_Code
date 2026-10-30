# frozen_string_literal: true

class AddPixelTestEventIdToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :pixel_test_event_id, :string
  end
end
