# frozen_string_literal: true

# Public endpoints for open and click tracking (no auth). Used by tracking pixel and link redirects in emails.
module EmailTool
  class TrackController < ActionController::Base
    skip_before_action :verify_authenticity_token, raise: false
    before_action :set_no_cache_headers

    # 1x1 transparent GIF (43 bytes)
    TRACKING_PIXEL = Base64.strict_decode64("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")

    def open
      token = params[:token].to_s.sub(/\.gif\z/, "")
      return head :not_found if token.blank?
      scheduled = ScheduledEmail.find_by(open_tracking_token: token)
      if scheduled
        scheduled.update_columns(opened_at: Time.current) if scheduled.opened_at.blank?
      end
      send_data TRACKING_PIXEL, type: "image/gif", disposition: "inline"
    end

    def click
      token = params[:token].to_s
      return redirect_to("https://example.com", allow_other_host: true) if token.blank?
      redirect_record = EmailClickRedirect.find_by(token: token)
      unless redirect_record
        return head :not_found
      end
      redirect_record.update_column(:clicked_at, Time.current) if redirect_record.clicked_at.blank?
      redirect_to redirect_record.destination_url, allow_other_host: true
    end

    private

    def set_no_cache_headers
      response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
      response.headers["Pragma"] = "no-cache"
    end
  end
end
