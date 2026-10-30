class AddLockPaidFeatureToSetting < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :lock_paid_feature, :boolean, default:false
  end
end
