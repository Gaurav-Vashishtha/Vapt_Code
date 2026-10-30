class ApplicationMailer < ActionMailer::Base
  default from: 'info@notifiktech.com'
  layout 'mailer'

  # Emailed links must not inherit Rails.routes default_url_options (e.g. port 3000 in development).
  def referral_program_mailer_url_options
    base = Rails.application.config.action_mailer.default_url_options&.symbolize_keys&.dup || {}
    host = ENV["REFERRAL_PORTAL_PUBLIC_HOST"].presence || base[:host]
    protocol = base[:protocol].to_s.presence || "https"
    protocol = protocol.to_s.delete_suffix("://")

    opts = { host: host, protocol: protocol }
    if host.to_s.match?(/\A(localhost|127\.0\.0\.1)\z/i)
      opts[:port] = base[:port] if base[:port].present?
    else
      # Explicitly clear inherited route port (e.g. :3000 in development).
      opts[:port] = nil
    end
    opts
  end
end
