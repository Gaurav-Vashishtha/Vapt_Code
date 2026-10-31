# frozen_string_literal: true

module SupportDashboard
  class ScheduledReportsController < ApplicationController
    before_action :authenticate_admin!
    before_action :set_definition,
                  only: %i[edit update test_deliver send_test_deliver]

    def index
      @definitions = ScheduledReportDefinition.ordered
    end

    def new
      @definition = ScheduledReportDefinition.new(
        output_format: "body_summary",
        sql_metrics: [],
        schedule_frequency: "daily",
      )
    end

    def create
      @definition = ScheduledReportDefinition.new(definition_params)
      apply_sql_metrics_from_json!(@definition)

      if @definition.errors.any?
        render :new, status: :unprocessable_entity
      elsif @definition.save
        redirect_to support_dashboard_scheduled_reports_path,
                    notice: "Global report created. Merchants will see it as an opt-in row in the app."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      attrs = definition_update_params.to_h
      attrs["sql_text"] = nil if @definition.builtin? && params[:clear_sql_text] == "1"

      if params.dig(:scheduled_report_definition, :sql_metrics_json).present?
        begin
          attrs["sql_metrics"] = parse_sql_metrics_json!(params[:scheduled_report_definition][:sql_metrics_json])
        rescue JSON::ParserError
          @definition.errors.add(:sql_metrics, "must be valid JSON")
          render :edit, status: :unprocessable_entity
          return
        end
      end

      if @definition.update(attrs)
        redirect_to support_dashboard_scheduled_reports_path,
                    notice: "Report definition updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def test_deliver; end

    def send_test_deliver
      shop = resolve_shop
      unless shop
        redirect_to test_deliver_support_dashboard_scheduled_report_path(@definition),
                    alert: "Shop not found. Check the domain or ID."
        return
      end

      test_email = params[:test_email].to_s.strip.presence
      recipients = test_email ? [test_email] : []
      if recipients.empty? && shop.owner_email.present?
        recipients = [shop.owner_email]
      end
      if recipients.empty?
        redirect_to test_deliver_support_dashboard_scheduled_report_path(@definition),
                    alert: "Enter a test email or use a shop with an owner email."
        return
      end

      ctx = ScheduledReports::ReportBuildContext.new(shop: shop, definition: @definition)
      payload = ScheduledReports::ReportContent.build(ctx)
      manage_url = ScheduledReports::ManageReportsUrl.for_shop(shop)

      ShopReportMailer.scheduled_report(
        recipients,
        "[TEST] #{payload.subject}",
        payload.body_text,
        payload.body_html,
        payload.attachment_name,
        payload.attachment_content,
        manage_reports_url: manage_url,
      ).deliver_now

      redirect_to support_dashboard_scheduled_reports_path,
                  notice: "Test email sent to #{recipients.join(', ')}."
    rescue StandardError => e
      redirect_to test_deliver_support_dashboard_scheduled_report_path(@definition),
                  alert: "Send failed: #{e.message}"
    end

    private

    def authenticate_admin!
      http_basic_authenticate_or_request_with(
        name: ENV.fetch("ADMIN_USER", nil),
        password: ENV.fetch("ADMIN_PASS", nil),
      )
    end

    def set_definition
      @definition = ScheduledReportDefinition.find(params[:id])
    end

    def resolve_shop
      if params[:shop_id].present?
        s = Shop.find_by(id: params[:shop_id])
        return s if s
      end

      domain = normalize_shop_domain(params[:shop_domain])
      return nil if domain.blank?

      Shop.find_by("LOWER(shopify_domain) = ?", domain)
    end

    def normalize_shop_domain(raw)
      s = raw.to_s.strip.downcase.delete_suffix("/")
      return "" if s.blank?

      s.include?(".") ? s : "#{s}.myshopify.com"
    end

    def apply_sql_metrics_from_json!(definition)
      raw = params.dig(:scheduled_report_definition, :sql_metrics_json)
      return if raw.blank?

      definition.sql_metrics = parse_sql_metrics_json!(raw)
    rescue JSON::ParserError
      definition.errors.add(:sql_metrics, "must be valid JSON")
    end

    # Accepts a JSON array. Also fixes a common paste: `{ ... }, { ... }]` (missing leading `[`).
    def parse_sql_metrics_json!(raw)
      s = raw.to_s.strip.delete_prefix("\uFEFF")
      raise JSON::ParserError, "blank" if s.blank?

      begin
        return JSON.parse(s)
      rescue JSON::ParserError
        if s.match?(/\A\{/) && s.match?(/\]\s*\z/)
          return JSON.parse("[#{s}")
        end
        if s.match?(/\A\{/) && !s.match?(/\A\[/)
          return JSON.parse("[#{s}]")
        end

        raise
      end
    end

    def definition_params
      params.require(:scheduled_report_definition).permit(
        :slug,
        :name,
        :output_format,
        :sql_text,
        :merchant_description,
        :email_body,
        :schedule_frequency,
        :default_subscribe_all,
        :default_send_hour,
        :default_send_minute,
        :default_weekly_send_wday,
      )
    end

    def definition_update_params
      params.require(:scheduled_report_definition).permit(
        :name,
        :output_format,
        :sql_text,
        :merchant_description,
        :email_body,
        :schedule_frequency,
        :default_subscribe_all,
        :default_send_hour,
        :default_send_minute,
        :default_weekly_send_wday,
      )
    end
  end
end
