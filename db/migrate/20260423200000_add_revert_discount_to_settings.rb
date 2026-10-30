# frozen_string_literal: true

class AddRevertDiscountToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :revert_discount, :boolean, default: false, null: false
  end
end
