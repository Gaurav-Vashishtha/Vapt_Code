# frozen_string_literal: true

module Rto
  class WebhookHealthMonitorJob
    include Sidekiq::Job
    sidekiq_options queue: :low, retry: 3

    BATCH = 500
    STALE_HOURS = 6

    def perform(after_shop_domain_id = 0)
      ids = ShopDomain.where("shop_domains.id > ?", after_shop_domain_id).order(:id).limit(BATCH).pluck(:id)
      return if ids.empty?

      cutoff = STALE_HOURS.hours.ago

      ids.each do |sdid|
        sd = ShopDomain.find_by(id: sdid)
        next if sd.blank?

        last = sd.last_webhook_received_at
        next if last.present? && last >= cutoff

        # Webhooks missing/stale; trigger reconciliation pull.
        ReconcileShopDomainJob.perform_async(sd.id, 72.hours.ago.iso8601)
      end

      self.class.perform_async(ids.last) if ids.size == BATCH
    end
  end
end

