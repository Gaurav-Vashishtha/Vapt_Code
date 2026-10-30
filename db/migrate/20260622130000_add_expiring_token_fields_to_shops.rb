class AddExpiringTokenFieldsToShops < ActiveRecord::Migration[7.2]
  # Shopify no longer accepts non-expiring offline access tokens on the Admin API.
  # Expiring tokens carry a refresh token + expiries that we must persist so we can
  # refresh them (and migrate legacy non-expiring tokens via token exchange).
  # All columns are nullable: legacy rows have none until they migrate at runtime.
  def change
    add_column :shops, :shopify_refresh_token, :string
    add_column :shops, :shopify_token_expires_at, :datetime
    add_column :shops, :shopify_refresh_token_expires_at, :datetime
    # Short-circuit guard for the concurrent-refresh race (see OfflineTokenService).
    add_column :shops, :shopify_token_refreshed_at, :datetime
  end
end
