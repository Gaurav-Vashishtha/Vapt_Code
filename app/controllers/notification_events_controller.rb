class NotificationEventsController < ApplicationController
    def track
      log = NotificationLog.where(
        shop_id: params[:shop_id],
        template_name: params[:template]
      ).order(scheduled_at: :desc).first
  
      log.update(clicked_at: Time.current) if log && log.clicked_at.nil?
  
      redirect_to "https://#{Shop.find(params[:shop_id]).shopify_domain}/admin/apps/cod-verification"
    end
  end
  