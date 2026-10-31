# frozen_string_literal: true

# Support dashboard → WhatsApp retries. Shows how the 131049 ("healthy
# ecosystem") retry flow is doing for MSG91 and BSP: config, outcome funnel,
# which attempt got messages through, why messages were dropped, what is due
# next, and the individual retry rows.
class WhatsappReattemptsDashboardController < ApplicationController
  before_action :authenticate_admin!

  DAY_OPTIONS = [1, 7, 30, 90].freeze
  PER_PAGE = 50

  def index
    @days = params[:days].to_i.presence_in(DAY_OPTIONS) || 7
    @flow = params[:flow].presence_in(WhatsappReattempt::FLOWS)
    @status = params[:status].presence_in(WhatsappReattempt::STATUSES)
    @shop_query = params[:shop].to_s.strip

    @policies = WhatsappReattempt::FLOWS.index_with { |f| Whatsapp::ReattemptPolicy.for(f) }
    @webhook_token_set = ENV.fetch("MSG91_WEBHOOK_TOKEN", nil).present?

    window = WhatsappReattempt.where('whatsapp_reattempts.created_at >= ?', @days.days.ago)
    window = window.where(flow: @flow) if @flow
    window = window.where(shop_id: matching_shop_ids) if @shop_query.present?

    @by_flow_status = window.group(:flow, :status).count
    @totals = window.group(:status).count
    @total = @totals.values.sum
    @through = @totals.values_at('sent', 'delivered').compact.sum
    @finished = @through + @totals.values_at('dropped', 'cancelled').compact.sum
    @success_attempts = window.where(status: %w[sent delivered]).group(:attempts).count.sort.to_h
    @drop_reasons = window.where(status: %w[dropped cancelled]).group(:drop_reason).count.sort_by { |_, n| -n }
    @error_codes = window.group(:error_code).count.sort_by { |_, n| -n }.first(8)
    @per_day = window.group("date_trunc('day', whatsapp_reattempts.created_at)").count.sort.to_h

    pending = WhatsappReattempt.where(status: 'pending')
    pending = pending.where(flow: @flow) if @flow
    now = Time.current
    @due = {
      'Overdue / due now' => pending.where('next_retry_at <= ?', now).count,
      'Next 1 hour' => pending.where(next_retry_at: now..(now + 1.hour)).count,
      'Next 3 hours' => pending.where(next_retry_at: now..(now + 3.hours)).count,
      'Next 24 hours' => pending.where(next_retry_at: now..(now + 24.hours)).count
    }
    @stuck_sending = WhatsappReattempt.where(status: 'sending')
                                      .where('updated_at < ?', now - WhatsappReattempt::STALE_SENDING_AFTER).count

    rows = window.order(id: :desc)
    rows = rows.where(status: @status) if @status
    @rows = rows.includes(:shop, :source).page(params[:page]).per(PER_PAGE)
  end

  # Resend everything due right now instead of waiting for the 5-minute cron.
  def run_now
    Whatsapp::ReattemptDispatchJob.perform_async
    redirect_to support_dashboard_whatsapp_retries_path(request.query_parameters.except('authenticity_token')),
                notice: 'Retry job queued — refresh in a minute.'
  end

  private

  def matching_shop_ids
    return [@shop_query.to_i] if @shop_query.match?(/\A\d+\z/)

    Shop.where('shopify_domain ILIKE ?', "%#{Shop.sanitize_sql_like(@shop_query)}%").limit(50).pluck(:id)
  end

  def authenticate_admin!
    http_basic_authenticate_or_request_with(name: ENV.fetch("ADMIN_USER", nil), password: ENV.fetch("ADMIN_PASS", nil))
  end
end
