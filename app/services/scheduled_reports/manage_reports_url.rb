# frozen_string_literal: true

module ScheduledReports
  # Deep link to the embedded app's Reports page in Shopify Admin.
  class ManageReportsUrl
    def self.for_shop(shop)
      domain = shop&.shopify_domain.to_s.strip
      return nil if domain.blank?

      key = ENV.fetch("SHOPIFY_API_KEY", "").to_s.strip
      return nil if key.blank?

      "https://#{domain}/admin/apps/#{key}/features/reports"
    end
  end
end
