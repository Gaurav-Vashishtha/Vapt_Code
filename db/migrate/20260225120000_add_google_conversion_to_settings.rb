# frozen_string_literal: true

class AddGoogleConversionToSettings < ActiveRecord::Migration[7.0]
  def change
    add_column :settings, :google_conversion_action, :string
    add_column :settings, :google_conversion_token, :string
    add_column :settings, :google_conversion_enabled, :boolean, default: false, null: false
  end
end
