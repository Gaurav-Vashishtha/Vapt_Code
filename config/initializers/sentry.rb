# if not Rails.env.development?
#   Sentry.init do |config|
#     config.dsn = ENV['SENTRY_RAILS_DSN']
#     config.breadcrumbs_logger = [:active_support_logger]

#     # Set tracesSampleRate to 1.0 to capture 100%
#     # of transactions for performance monitoring.
#     # We recommend adjusting this value in production
#     config.traces_sample_rate = Rails.env.production? ? 0 : 0
#     # or
#     config.traces_sampler = lambda do |context|
#       true
#     end
#     config.environment = 'production'
#   end
# end


Sentry.init do |config|
    config.dsn = 'https://75f3a6369ee0547acb86fc90b185bbe0@o4510113936703488.ingest.us.sentry.io/4510113937948672'
    config.breadcrumbs_logger = [:active_support_logger, :http_logger]
  
    # Add data like request headers and IP for users,
    # see https://docs.sentry.io/platforms/ruby/data-management/data-collected/ for more info
    config.send_default_pii = true
  end