# frozen_string_literal: true

module ScheduledReports
  # In-memory report shape for SQL/runner and mail previews (no DB row, no scheduled_report_assignment).
  ReportBuildContext = Struct.new(:shop, :definition, keyword_init: true) do
    delegate :sql_text, :name, :output_format, to: :definition

    def report_kind
      definition.slug
    end

    def scheduled_report_definition
      definition
    end

    def deliver_timezone
      timezone_holder.deliver_timezone
    end

    def deliver_timezone_name
      timezone_holder.deliver_timezone_name
    end

    private

    def timezone_holder
      @timezone_holder ||= ScheduledShopReport.new(shop: shop)
    end
  end
end
