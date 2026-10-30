class EngagementDashboardController < ApplicationController
  before_action :authenticate_admin!

  def index
    # Default to last 7 days
    days = params[:days]&.to_i || 7
    @days = days
    
    # Calculate date range
    @end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.today
    @start_date = @end_date - (days - 1).days
    @date_range = @start_date.beginning_of_day..@end_date.end_of_day
    
    # Get engagement data
    @engagement_data = EngagementTrackingService.calculate_engagement(@date_range)
    @summary = EngagementTrackingService.total_engagement_summary(@date_range)
    
    # Quick filter options
    @quick_filters = [
      { label: 'Last 1 Day', days: 1 },
      { label: 'Last 7 Days', days: 7 },
      { label: 'Last 30 Days', days: 30 },
      { label: 'Last 90 Days', days: 90 }
    ]
  end

  private

  def authenticate_admin!
    http_basic_authenticate_or_request_with(
      name: ENV["ADMIN_USER"],
      password: ENV["ADMIN_PASS"]
    )
  end
end

