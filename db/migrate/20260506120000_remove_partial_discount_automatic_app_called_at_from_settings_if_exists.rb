class RemovePartialDiscountAutomaticAppCalledAtFromSettingsIfExists < ActiveRecord::Migration[7.0]
  def up
    return unless column_exists?(:settings, :partial_discount_automatic_app_called_at)

    remove_column :settings, :partial_discount_automatic_app_called_at
  end

  def down
    return if column_exists?(:settings, :partial_discount_automatic_app_called_at)

    add_column :settings, :partial_discount_automatic_app_called_at, :datetime
  end
end

