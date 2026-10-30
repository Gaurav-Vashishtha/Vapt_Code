# frozen_string_literal: true

# google_conversion_label was removed in 20260311120000; tag / web pixel need it again.
class AddGoogleConversionLabelToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :google_conversion_label, :string unless column_exists?(:settings, :google_conversion_label)
  end
end
