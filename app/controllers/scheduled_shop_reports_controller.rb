# frozen_string_literal: true

class ScheduledShopReportsController < AuthenticatedController
  before_action :set_shop
  before_action :set_report, only: %i[show update send_now]

  def index
    ScheduledShopReport.sync_subscriptions_for_shop!(@shop)
    reports =
      @shop
        .scheduled_shop_reports
        .includes(:scheduled_report_definition)
        .references(:scheduled_report_definition)
        .order(
          "scheduled_report_definitions.slug ASC",
          "scheduled_shop_reports.id ASC",
        )
    render json: reports.map(&:as_merchant_json)
  end

  def show
    render json: @report.as_merchant_json
  end

  def update
    attrs = update_params

    if @report.update(attrs)
      render json: @report.reload.as_merchant_json
    else
      render json: { errors: @report.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def send_now
    unless @report.effective_enabled?
      render json: { errors: ["Turn on scheduled email for this report before sending."] }, status: :unprocessable_entity
      return
    end
    unless @report.feature_ready?
      render json: { errors: ["This report is not available until its feature is enabled for your shop."] }, status: :unprocessable_entity
      return
    end
    if @report.recipient_list.blank?
      render json: { errors: ["Add at least one recipient email (or a shop owner email)."] }, status: :unprocessable_entity
      return
    end

    # Use `default` so Send now works even when Sidekiq is started without config/sidekiq.yml
    # (that setup often listens only to "default"). Scheduled cron/drain still use scheduled_report_delivery.
    ScheduledReports::DeliverReportJob.set(queue: :default).perform_async(
      @report.id,
      { "send_now" => true },
    )
    render json: { ok: true, message: "Report email queued. It should arrive within a few minutes." }
  end

  private

  def set_report
    @report =
      @shop
        .scheduled_shop_reports
        .includes(:scheduled_report_definition)
        .find(params[:id])
  end

  def update_params
    params.require(:scheduled_shop_report).permit(
      :recipient_emails,
      :timezone,
      :enabled,
      :send_hour,
      :send_minute,
      :weekly_send_wday,
    )
  end
end
