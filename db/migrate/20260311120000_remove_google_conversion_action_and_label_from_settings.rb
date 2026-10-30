# frozen_string_literal: true

class RemoveGoogleConversionActionAndLabelFromSettings < ActiveRecord::Migration[7.0]
  def up
    remove_column :settings, :google_conversion_action, :string if column_exists?(:settings, :google_conversion_action)
    remove_column :settings, :google_conversion_label, :string if column_exists?(:settings, :google_conversion_label)
  end

  def down
    add_column :settings, :google_conversion_action, :string unless column_exists?(:settings, :google_conversion_action)
    add_column :settings, :google_conversion_label, :string unless column_exists?(:settings, :google_conversion_label)
  end
end
