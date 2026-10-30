# frozen_string_literal: true

# Align DB default with app: shops that ran add_revert_discount when default was true.
class ChangeRevertDiscountDefaultToFalse < ActiveRecord::Migration[7.2]
  def up
    return unless column_exists?(:settings, :revert_discount)

    change_column_default :settings, :revert_discount, false
  end

  def down
    return unless column_exists?(:settings, :revert_discount)

    change_column_default :settings, :revert_discount, true
  end
end
