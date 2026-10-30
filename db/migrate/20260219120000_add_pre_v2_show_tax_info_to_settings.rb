# frozen_string_literal: true

class AddPreV2ShowTaxInfoToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :pre_v2_show_tax_info, :boolean, default: false, null: false
  end
end
