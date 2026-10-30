# frozen_string_literal: true

module CodForm
  # The cache every COD Form service reads and writes: Rails.cache.
  #
  # Development runs with a null cache unless `rails dev:cache` was switched on, and the form
  # then asks Shopify for the shop, the variants, the automatic discounts and the tax again on
  # every single request (seconds per quote). In that one case an in-process memory store is
  # used instead, so the form is as fast locally as it is in production. Production, staging
  # and tests always get Rails.cache itself.
  module Cache
    class << self
      def store
        return Rails.cache unless Rails.env.development? && Rails.cache.is_a?(ActiveSupport::Cache::NullStore)

        @memory ||= ActiveSupport::Cache::MemoryStore.new(size: 32.megabytes)
      end
    end
  end
end
