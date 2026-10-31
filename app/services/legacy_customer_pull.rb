# frozen_string_literal: true

module LegacyCustomerPull
  def self.enabled?
    ENV.fetch('LEGACY_CUSTOMER_PULL_ENABLED', 'false').to_s.downcase == 'true' && !CustomerSyncControl.killed?
  end
end
