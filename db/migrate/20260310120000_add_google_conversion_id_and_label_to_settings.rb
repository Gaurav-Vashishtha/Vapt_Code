# Adds Conversion ID + Conversion label columns (Flexype/tag pattern).
# Keeps google_conversion_action for backward compatibility.
class AddGoogleConversionIdAndLabelToSettings < ActiveRecord::Migration[7.0]
  def change
    add_column :settings, :google_conversion_id, :string
    add_column :settings, :google_conversion_label, :string
  end
end
