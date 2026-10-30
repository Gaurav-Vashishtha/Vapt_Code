# frozen_string_literal: true

# Internal COD King ops dashboard at /codk-ops.
#
# - Inherits ActionController::Base on purpose: no Shopify session/JWT filters.
# - HTTP Basic auth from ENV CODK_OPS_USER / CODK_OPS_PASSWORD (min 12 chars).
#   Not configured -> 503 (fails closed).
# - The Svelte build lives in ops-dashboard/build and is served through this
#   controller, so even the JS/CSS sit behind the login.
# - The API only reads small rollup tables; heavy work runs in Sidekiq.
class CodkOpsController < ActionController::Base
  BUILD_DIR = Rails.root.join('ops-dashboard', 'build').freeze
  MIN_PASSWORD_LENGTH = 12

  # Read-only GETs behind Basic auth, no session cookie: CSRF protection adds nothing here. Left on, Rails'
  # cross-origin-JS check rejects serving the .js bundle (InvalidCrossOriginRequest -> 422 error page).
  skip_forgery_protection

  rate_limit to: 240, within: 1.minute, by: -> { request.remote_ip }, with: -> { head :too_many_requests }
  before_action :require_basic_auth
  after_action :private_no_index

  def overview
    render json: Ops::Overview.cached(from: params[:from], to: params[:to])
  end

  # Serves the Svelte SPA: real files from the build dir, index.html otherwise.
  def app
    return render(plain: 'ops-dashboard build not found (run npm run build in ops-dashboard/)', status: :service_unavailable) unless BUILD_DIR.join('index.html').file?

    file = resolve_asset(params[:path].to_s)
    if file
      immutable = file.to_s.include?('/assets/')
      response.headers['Cache-Control'] = immutable ? 'private, max-age=31536000, immutable' : 'private, no-store'
      send_file file, disposition: 'inline', type: Rack::Mime.mime_type(file.extname, 'application/octet-stream')
    elsif params[:path].to_s.start_with?('assets/')
      head :not_found # a missing bundle must be a 404, never the HTML page (browsers reject HTML as a script)
    else
      response.headers['Cache-Control'] = 'private, no-store'
      send_file BUILD_DIR.join('index.html'), disposition: 'inline', type: 'text/html'
    end
  end

  private

  def require_basic_auth
    user = ENV['CODK_OPS_USER'].to_s
    password = ENV['CODK_OPS_PASSWORD'].to_s
    return head(:service_unavailable) if user.blank? || password.length < MIN_PASSWORD_LENGTH

    authenticate_or_request_with_http_basic('COD King Ops') do |u, p|
      user_ok = ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(u.to_s), Digest::SHA256.hexdigest(user))
      pass_ok = ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(p.to_s), Digest::SHA256.hexdigest(password))
      user_ok & pass_ok
    end
  end

  # Only existing regular files inside the build dir; blocks ../ traversal.
  def resolve_asset(relative)
    return nil if relative.blank?

    candidate = BUILD_DIR.join(relative).cleanpath
    root = BUILD_DIR.to_s + File::SEPARATOR
    candidate.to_s.start_with?(root) && candidate.file? ? candidate : nil
  end

  def private_no_index
    response.headers['X-Robots-Tag'] = 'noindex, nofollow'
  end
end
