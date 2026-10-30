module ApplicationHelper
    def current_referral_partner
        @current_referral_partner ||= ReferralPartner.find(session[:referral_partner_id]) if session[:referral_partner_id]
      end
    
      def current_referral_admin
        @current_referral_admin ||= session[:referral_admin_user] || 'admin'
      end
    
      def referral_navigation_active?(path)
        current_page?(path) ? 'font-semibold text-blue-600' : 'text-gray-600 hover:text-gray-800'
      end
    
      def admin_navigation_active?(path)
        current_page?(path) ? 'font-semibold text-white' : 'text-indigo-200 hover:text-white'
      end
    
      def format_payout_period(from_date, to_date)
        if from_date.year == to_date.year
          if from_date.month == to_date.month
            "#{from_date.strftime('%b %d')} - #{to_date.strftime('%d, %Y')}"
          else
            "#{from_date.strftime('%b %d')} - #{to_date.strftime('%b %d, %Y')}"
          end
        else
          "#{from_date.strftime('%m/%d/%Y')} - #{to_date.strftime('%m/%d/%Y')}"
        end
      end
    
      def job_status_class(status)
        case status.to_s
        when 'completed'
          'bg-green-100 text-green-800'
        when 'failed'
          'bg-red-100 text-red-800'
        when 'running'
          'bg-blue-100 text-blue-800'
        else
          'bg-gray-100 text-gray-800'
        end
      end

  # URL to unsubscribe an email (for use in emails or docs). Params: email, optional source (e.g. "email_tool").
  def unsubscribe_url(email, source: "general")
    base = "#{request.base_url}" rescue (Rails.application.config.action_mailer.default_url_options[:host].then { |h| "https://#{h}" })
    encoded_email = ERB::Util.url_encode(email.to_s.strip)
    encoded_source = ERB::Util.url_encode(source.to_s)
    "#{base}/unsubscribe?email=#{encoded_email}&source=#{encoded_source}"
  end
end
