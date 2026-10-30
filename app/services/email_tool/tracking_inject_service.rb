# frozen_string_literal: true

# Injects open-tracking pixel and wraps links with click-tracking redirects into the email HTML body.
module EmailTool
  class TrackingInjectService
    def self.call(scheduled_email, html_body, base_url: nil)
      new(scheduled_email, html_body, base_url: base_url).call
    end

    def initialize(scheduled_email, html_body, base_url: nil)
      @scheduled_email = scheduled_email
      @html_body = html_body.to_s
      @base_url = base_url.presence || default_base_url
    end

    def call
      return @html_body if @html_body.blank?
      body = wrap_links_for_click_tracking(@html_body)
      body = append_open_pixel(body)
      body = append_unsubscribe_link(body)
      body
    end

    private

    def default_base_url
      host = Rails.application.config.action_mailer.default_url_options[:host]
      protocol = Rails.application.config.action_mailer.default_url_options[:protocol] || "https"
      "#{protocol}://#{host}"
    end

    def append_open_pixel(html)
      token = @scheduled_email.open_tracking_token
      return html if token.blank?
      pixel_url = "#{@base_url}/email_tool/track/open/#{token}.gif"
      pixel = "<img src=\"#{pixel_url}\" width=\"1\" height=\"1\" alt=\"\" style=\"display:none\" />"
      # Always append at the very end so it's never lost during HTML parsing/serialization
      if html.include?("</body>")
        html.sub("</body>", "#{pixel}</body>")
      else
        "#{html}#{pixel}"
      end
    end

    def append_unsubscribe_link(html)
      email = @scheduled_email.recipient_email
      return html if email.blank?
      url = unsubscribe_url_for(email, source: "email_tool")
      link = "<p style=\"font-size:11px;color:#666;margin-top:1em;\"><a href=\"#{ERB::Util.html_escape(url)}\">Unsubscribe from these emails</a></p>"
      if html.include?("</body>")
        html.sub("</body>", "#{link}</body>")
      else
        "#{html}#{link}"
      end
    end

    def unsubscribe_url_for(email, source: "general")
      encoded_email = ERB::Util.url_encode(email.to_s.strip)
      encoded_source = ERB::Util.url_encode(source.to_s)
      "#{@base_url}/unsubscribe?email=#{encoded_email}&source=#{encoded_source}"
    end

    def wrap_links_for_click_tracking(html)
      doc = Nokogiri::HTML(html)
      doc.css("a[href]").each do |a|
        href = a["href"].to_s.strip
        next if href.blank? || href.start_with?("mailto:") || href.start_with?("#")
        redirect = @scheduled_email.email_click_redirects.create!(
          token: SecureRandom.urlsafe_base64(24),
          destination_url: href
        )
        a["href"] = "#{@base_url}/email_tool/track/click/#{redirect.token}"
      end
      # Return serialized HTML (fragment or full doc)
      doc.at("body") ? doc.at("body").to_html : doc.to_html
    end
  end
end
