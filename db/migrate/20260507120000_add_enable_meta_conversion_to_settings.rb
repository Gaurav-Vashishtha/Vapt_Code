# frozen_string_literal: true

class AddEnableMetaConversionToSettings < ActiveRecord::Migration[7.2]
  def up
    return if column_exists?(:settings, :enable_meta_conversion)
    add_column :settings, :enable_meta_conversion, :boolean, default: true, null: false
  end

  def down
    return unless column_exists?(:settings, :enable_meta_conversion)
    remove_column :settings, :enable_meta_conversion
  end
end
