# frozen_string_literal: true

module SupportDashboard
  class ScheduledReportDeliveriesController < ApplicationController
    before_action :authenticate_admin!

    def index
      @from = parse_date(params[:from]) || 14.days.ago.to_date
      @to = parse_date(params[:to]) || Date.current
      @status = params[:status].presence || "sent"
      @report_kind = params[:report_kind].presence
      @shop_domain = params[:shop_domain].to_s.strip.presence

      scope = ScheduledReportDelivery.all
      scope = scope.where(sent_at: @from.beginning_of_day..@to.end_of_day)
      scope = scope.where(status: @status) if @status.present?
      scope = scope.where(report_kind: @report_kind) if @report_kind.present?

      if @shop_domain.present?
        domain = normalize_shop_domain(@shop_domain)
        scope = scope.joins(:shop).where("LOWER(shops.shopify_domain) = ?", domain)
      end

      @kinds = ScheduledReportDelivery.distinct.order(:report_kind).pluck(:report_kind)

      rows =
        scope
          .select("DATE(sent_at) AS day, report_kind, COUNT(*) AS count")
          .group("DATE(sent_at)", "report_kind")
          .order("day DESC, report_kind ASC")

      @counts_by_day = {}
      rows.each do |r|
        day = r.day
        kind = r.report_kind
        @counts_by_day[day] ||= {}
        @counts_by_day[day][kind] = r.count.to_i
      end

      @days = @counts_by_day.keys.sort.reverse
    end

    private

    def authenticate_admin!
      http_basic_authenticate_or_request_with(
        name: ENV["ADMIN_USER"],
        password: ENV["ADMIN_PASS"],
      )
    end

    def parse_date(raw)
      s = raw.to_s.strip
      return nil if s.blank?
      Date.parse(s)
    rescue ArgumentError
      nil
    end

    def normalize_shop_domain(raw)
      s = raw.to_s.strip.downcase.delete_suffix("/")
      return "" if s.blank?
      s.include?(".") ? s : "#{s}.myshopify.com"
    end
  end
end

