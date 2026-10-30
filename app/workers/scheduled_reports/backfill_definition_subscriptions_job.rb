# frozen_string_literal: true

module ScheduledReports
  # Creates / updates scheduled_shop_reports for every shop when admin enables default_subscribe_all.
  # Chained batches to avoid blocking the request and to limit memory per job.
  class BackfillDefinitionSubscriptionsJob
    include Sidekiq::Job
    sidekiq_options queue: :low, retry: 3

    BATCH = 300

    def perform(definition_id, after_shop_id = 0)
      defn = ScheduledReportDefinition.find_by(id: definition_id)
      return if defn.blank? || !defn.default_subscribe_all?

      ids = Shop.where("shops.id > ?", after_shop_id).order(:id).limit(BATCH).pluck(:id)
      return if ids.empty?

      ids.each do |sid|
        shop = Shop.find_by(id: sid)
        next unless shop

        ScheduledShopReport.ensure_for_shop_and_definition!(shop, defn)
      end

      self.class.perform_async(definition_id, ids.last) if ids.size == BATCH
    end
  end
end
