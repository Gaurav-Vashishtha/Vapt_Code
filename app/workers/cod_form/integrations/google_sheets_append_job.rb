# frozen_string_literal: true

module CodForm
  module Integrations
    # INT-1 (ARCHITECTURE.md I.5): appends one row per form order to the merchant's sheet.
    #   GoogleSheetsAppendJob.perform_async(session_id)
    # Queue default, retry 8 (Sidekiq's exponential back-off = "near real time with retries").
    # Idempotent per order: CodForm::Cache.store key codf:gs:<order_id> is written after success.
    # Only transient failures are retried; a revoked account or a missing sheet marks the
    # integration as "error" (shown to the merchant) and stops.
    class GoogleSheetsAppendJob < ApplicationJob
      sidekiq_options queue: "default", retry: 8

      PROVIDER = "google_sheets"
      DONE_TTL = 30.days
      LOCK_TTL = 2.minutes
      SESSION_KEYS = %w[order_id order_name order_total_cents currency contact address quote_snapshot attribution
                        custom_fields].freeze

      sidekiq_retries_exhausted do |job, _exception|
        session = CodForm::Tracking::ServerDispatchJob.find_session(job["args"].first)
        integration = session && CodForm::Integration.find_by(shop_id: session.shop_id, provider: PROVIDER)
        Registry.error!(integration, "Google Sheets could not be reached. Some orders were not added.") if integration
      end

      def perform(session_id)
        session = CodForm::Tracking::ServerDispatchJob.find_session(session_id)
        return if session.nil? || session.order_id.blank? || session.is_test

        shop = session.shop
        return if shop.nil? || !GoogleSheets::Client.configured?

        integration = Registry.active(shop, PROVIDER)
        return if integration.nil?

        config = integration.config.is_a?(Hash) ? integration.config : {}
        spreadsheet_id = config["spreadsheet_id"].to_s
        return if spreadsheet_id.empty?

        done_key = "codf:gs:#{session.order_id}"
        return if CodForm::Cache.store.exist?(done_key)

        lock_key = "codf:gs:lock:#{session.order_id}"
        return unless CodForm::Cache.store.write(lock_key, 1, unless_exist: true, expires_in: LOCK_TTL)

        begin
          append(integration, config, spreadsheet_id, session, shop)
          CodForm::Cache.store.write(done_key, 1, expires_in: DONE_TTL)
          Registry.success!(integration)
        rescue GoogleSheets::Client::AuthError, GoogleSheets::Client::RequestError => e
          # The messages of these two errors are written by the client and carry no buyer data.
          Registry.error!(integration, e.message)
          Rails.logger.warn("[codf/sheets] shop=#{shop.id} order=#{session.order_id} stopped: #{e.class}")
        ensure
          CodForm::Cache.store.delete(lock_key)
        end
        # GoogleSheets::Client::TransientError propagates: Sidekiq retries.
      end

      private

      def append(integration, config, spreadsheet_id, session, shop)
        client = GoogleSheets::Client.new(integration)
        sheet_name = config["sheet_name"].to_s
        columns = GoogleSheets::RowBuilder.normalize_columns(config["columns"])

        header_mark = Digest::SHA256.hexdigest("#{spreadsheet_id}/#{sheet_name}/#{columns.join(',')}")[0, 16]
        header_key = "codf:gs:header:#{integration.id}:#{header_mark}"
        unless CodForm::Cache.store.exist?(header_key)
          if client.empty_sheet?(spreadsheet_id, sheet_name)
            client.append_row(spreadsheet_id, sheet_name, GoogleSheets::RowBuilder.header(columns))
          end
          CodForm::Cache.store.write(header_key, 1, expires_in: 7.days)
        end

        data = session.attributes.slice(*SESSION_KEYS)
        zone = CodForm::Analytics::ShopTime.zone(shop)
        data["ordered_at"] = (session.ordered_at || Time.current).in_time_zone(zone).strftime("%Y-%m-%d %H:%M:%S")
        client.append_row(spreadsheet_id, sheet_name, GoogleSheets::RowBuilder.build(columns: columns, session: data))
      end
    end
  end
end
