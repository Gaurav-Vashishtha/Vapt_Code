# frozen_string_literal: true

module CodForm
  # Debounced write of the `codk.cod_form` shop metafield (C.1).
  #
  #   CodForm::MetafieldSyncJob.perform_async(shop_id)   # K.9 — called by ShopConfig#bump_version!
  #
  # A burst of admin writes (the designer saves on every publish, CSV import, bulk edits) becomes
  # one Shopify call: the first enqueue of a burst schedules the real run a few seconds later and
  # the following ones are dropped while that run is pending. The run reads the configuration
  # after clearing the marker, and CodForm::MetafieldSyncService only writes when
  # `config_version > metafield_synced_version`, so no change is ever lost.
  class MetafieldSyncJob < ApplicationJob
    sidekiq_options queue: :default, retry: 3

    DEBOUNCE_SECONDS = 3
    MARKER_TTL = 60

    def self.marker_key(shop_id)
      "codf:mfsync:pending:#{shop_id}"
    end

    # run_now: true for the scheduled run (internal). force: write even when the versions match
    # (kill switch, cap state change, Setting change).
    def perform(shop_id, run_now = false, force = false)
      unless run_now
        key = self.class.marker_key(shop_id)
        if force
          CodForm::Cache.store.write(key, "force", expires_in: MARKER_TTL)
          self.class.perform_in(DEBOUNCE_SECONDS, shop_id, true, true)
        elsif CodForm::Cache.store.write(key, "1", expires_in: MARKER_TTL, unless_exist: true)
          self.class.perform_in(DEBOUNCE_SECONDS, shop_id, true, false)
        end
        return
      end

      CodForm::Cache.store.delete(self.class.marker_key(shop_id))
      shop = Shop.find_by(id: shop_id)
      return if shop.nil?

      result = CodForm::MetafieldSyncService.call(shop, force: force ? true : false)
      # Let Sidekiq retry a failed Shopify write (3 attempts).
      raise "cod_form metafield sync failed shop_id=#{shop_id}" if result[:status] == :failed
    end
  end
end
