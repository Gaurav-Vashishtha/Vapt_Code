class Rack::Attack

  ### Configure Cache ###

  # If you don't want to use Rails.cache (Rack::Attack's default), then
  # configure it here.
  #
  # Note: The store is only used for throttling (not blocklisting and
  # safelisting). It must implement .increment and .write like
  # ActiveSupport::Cache::Store

  # Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new 

  ### Throttle Spammy Clients ###

  # If any single client IP is making tons of requests, then they're
  # probably malicious or a poorly-configured scraper. Either way, they
  # don't deserve to hog all of the app server's CPU. Cut them off!
  #
  # Note: If you're serving assets through rack, those requests may be
  # counted by rack-attack and this throttle may be activated too
  # quickly. If so, enable the condition to exclude them from tracking.

  # Throttle all requests by IP (60rpm)
  #
  # Key: "rack::attack:#{Time.now.to_i/:period}:req/ip:#{req.ip}"
  WEBHOOK_INGEST_PATH = %r{\A/api/webhooks/[^/]+/[^/]+\z}.freeze

  throttle('req/ip', limit: 40, period: 5.seconds) do |req|
    next if req.path == '/order_confirmations' && req.post?
    next if req.path.match?(WEBHOOK_INGEST_PATH)

    req.ip
  end

  # Checkout platforms post every abandoned cart from a handful of egress IPs,
  # so a flash sale trips the 40-per-5s cap above and we lose carts to 429s that
  # the provider may never retry. Bucket per endpoint token instead, so one busy
  # merchant cannot starve another.
  throttle('webhooks/endpoint', limit: 300, period: 5.seconds) do |req|
    req.path.split('/').last if req.post? && req.path.match?(WEBHOOK_INGEST_PATH)
  end

  # Backstop so an unknown-token flood still costs the sender something.
  throttle('webhooks/ip', limit: 3000, period: 60.seconds) do |req|
    req.ip if req.post? && req.path.match?(WEBHOOK_INGEST_PATH)
  end

  ### Prevent Brute-Force Login Attacks ###

  # The most common brute-force login attack is a brute-force password
  # attack where an attacker simply tries a large number of emails and
  # passwords to see if any credentials match.
  #
  # Another common method of attack is to use a swarm of computers with
  # different IPs to try brute-forcing a password for a specific account.

  # Throttle POST requests to /login by IP address
  #
  # Key: "rack::attack:#{Time.now.to_i/:period}:logins/ip:#{req.ip}"
  throttle('logins/ip', limit: 5, period: 20.seconds) do |req|
    if req.path == '/login'
      req.ip
    end
  end

  # Throttle POST requests to /login by email param
  #
  # Key: "rack::attack:#{Time.now.to_i/:period}:logins/email:#{normalized_email}"
  #
  # Note: This creates a problem where a malicious user could intentionally
  # throttle logins for another user and force their login requests to be
  # denied, but that's not very common and shouldn't happen to you. (Knock
  # on wood!)
  throttle('logins/shop', limit: 5, period: 20.seconds) do |req|
    if req.path == '/login'
      # Normalize the email, using the same logic as your authentication process, to
      # protect against rate limit bypasses. Return the normalized email if present, nil otherwise.
      req.params['shop'].to_s.downcase.gsub(/\s+/, "").presence
    end
  end

  ### COD Form storefront API (docs/cod-form/ARCHITECTURE.md D.0.4) ###

  # name => [limit, period in seconds]. Limits can be overridden without a deploy through
  # cod_form_global_settings.settings["rate_limits"] ({"codf/session/ip" => {"limit" => 60}});
  # the overrides are read once, on the first throttled-path request after boot.
  COD_FORM_THROTTLES = {
    'codf/session/ip'  => [30, 60],
    'codf/quote/ip'    => [120, 60],
    'codf/orders/ip'   => [30, 600],
    'codf/orders/shop' => [600, 60],
    'codf/otp/ip'      => [10, 600],
    'codf/events/ip'   => [240, 60],
    'cod_orders/ip'    => [30, 600]
  }.freeze
  COD_FORM_API_PREFIX = '/api/form/'.freeze

  def self.cod_form_limit(name)
    @cod_form_limits ||= begin
      overrides = CodForm::GlobalSetting.current.rate_limits
      COD_FORM_THROTTLES.to_h do |key, (limit, _period)|
        custom = overrides[key].is_a?(Hash) ? overrides[key]['limit'].to_i : 0
        [key, custom.positive? ? custom : limit]
      end
    rescue StandardError
      # Table missing (first deploy before migrations) or cache down: keep the defaults.
      COD_FORM_THROTTLES.transform_values(&:first)
    end
    @cod_form_limits.fetch(name)
  end

  # Which codf/* bucket a request belongs to (nil = not a COD Form API request).
  def self.cod_form_bucket(req)
    path = req.path
    return nil unless path.start_with?(COD_FORM_API_PREFIX)

    rest = path.delete_prefix(COD_FORM_API_PREFIX).chomp('/')
    if req.get?
      return rest.start_with?('geo/') || rest == 'config' ? 'codf/quote/ip' : nil
    end
    return nil unless req.post?

    case rest
    when 'session' then 'codf/session/ip'
    when 'quote', 'contact', 'orders/status' then 'codf/quote/ip'
    when 'orders', 'handoff', 'upsell_accept' then 'codf/orders/ip'
    when 'otp/send', 'otp/verify' then 'codf/otp/ip'
    when 'events' then 'codf/events/ip'
    end
  end

  %w[codf/session/ip codf/quote/ip codf/orders/ip codf/otp/ip codf/events/ip].each do |name|
    throttle(name, limit: proc { |_req| Rack::Attack.cod_form_limit(name) }, period: COD_FORM_THROTTLES.fetch(name).last) do |req|
      req.ip if Rack::Attack.cod_form_bucket(req) == name
    end
  end

  # Per shop, so one shop under attack (or a flash sale) cannot be used to flood order creation.
  # Keyed on the query string only: the body is never parsed here.
  throttle('codf/orders/shop', limit: proc { |_req| Rack::Attack.cod_form_limit('codf/orders/shop') },
                               period: COD_FORM_THROTTLES.fetch('codf/orders/shop').last) do |req|
    if req.post? && req.path.chomp('/') == '/api/form/orders'
      req.GET['shop'].to_s.downcase.strip[0, 100].presence
    end
  end

  # Legacy Express endpoint (D.12): public and previously unthrottled.
  throttle('cod_orders/ip', limit: proc { |_req| Rack::Attack.cod_form_limit('cod_orders/ip') },
                            period: COD_FORM_THROTTLES.fetch('cod_orders/ip').last) do |req|
    req.ip if req.post? && req.path.chomp('/') == '/api/cod_orders'
  end

  # /api/form/* answers a throttle with the form's JSON error envelope (D.0.3); every other
  # path keeps Rack::Attack's default response.
  cod_form_default_throttled_responder = Rack::Attack.configuration.throttled_responder
  self.throttled_responder = lambda do |request|
    unless request.path.start_with?(COD_FORM_API_PREFIX)
      next cod_form_default_throttled_responder.call(request) if cod_form_default_throttled_responder

      next [429, { 'content-type' => 'text/plain' }, ["Retry later\n"]]
    end

    match_data = request.env['rack.attack.match_data'] || {}
    period = match_data[:period].to_i
    retry_after = period.positive? ? period - (match_data[:epoch_time].to_i % period) : 60
    body = {
      'ok' => false,
      'error' => {
        'code' => 'rate_limited', 'message_key' => 'error_rate_limited', 'fallback' => nil,
        'fields' => {}, 'retry_after' => retry_after
      }
    }
    [429, { 'content-type' => 'application/json; charset=utf-8', 'retry-after' => retry_after.to_s, 'cache-control' => 'no-store' },
     [body.to_json]]
  end

  ### Custom Throttle Response ###

  # By default, Rack::Attack returns an HTTP 429 for throttled responses,
  # which is just fine.
  #
  # If you want to return 503 so that the attacker might be fooled into
  # believing that they've successfully broken your app (or you just want to
  # customize the response), then uncomment these lines.
  # self.throttled_response = lambda do |env|
  #  [ 503,  # status
  #    {},   # headers
  #    ['']] # body
  # end
end