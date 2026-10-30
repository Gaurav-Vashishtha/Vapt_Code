class AddConversionTrackingToSettings < ActiveRecord::Migration[7.0]
  def up
    unless column_exists?(:settings, :conversion_tracking)
      add_column :settings, :conversion_tracking, :boolean, default: true, null: false
    end

    if column_exists?(:settings, :enable_meta_conversion) || column_exists?(:settings, :google_conversion_enabled)
      execute <<~SQL
        UPDATE settings
        SET conversion_tracking = (
          COALESCE(enable_meta_conversion, true) <> false
          OR COALESCE(google_conversion_enabled, false) = true
        )
      SQL
    end

    remove_column :settings, :enable_meta_conversion if column_exists?(:settings, :enable_meta_conversion)
    remove_column :settings, :google_conversion_enabled if column_exists?(:settings, :google_conversion_enabled)
    remove_column :settings, :google_ads_refresh_token if column_exists?(:settings, :google_ads_refresh_token)
    remove_column :settings, :google_ads_customer_id if column_exists?(:settings, :google_ads_customer_id)
  end

  def down
    add_column :settings, :enable_meta_conversion, :boolean, default: true, null: false unless column_exists?(:settings, :enable_meta_conversion)
    add_column :settings, :google_conversion_enabled, :boolean, default: false, null: false unless column_exists?(:settings, :google_conversion_enabled)
    add_column :settings, :google_ads_refresh_token, :text unless column_exists?(:settings, :google_ads_refresh_token)
    add_column :settings, :google_ads_customer_id, :string unless column_exists?(:settings, :google_ads_customer_id)
    remove_column :settings, :conversion_tracking if column_exists?(:settings, :conversion_tracking)
  end
end
