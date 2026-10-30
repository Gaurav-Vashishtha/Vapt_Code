# frozen_string_literal: true

class AddMetaEventsEnabledToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :meta_events_enabled, :boolean, default: false, null: true
  end
end
