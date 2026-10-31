Rails.application.configure do
  config.hosts << "renaissance-opt-automation-assignments.trycloudflare.com"
  config.hosts << ENV.fetch("APP_HOST", nil) if ENV.fetch("APP_HOST", nil).present?
  # Every restart of `cloudflared tunnel` hands out a new subdomain, so match
  # the whole domain rather than editing this file each time.
  config.hosts << /\A[-a-z0-9]+\.trycloudflare\.com\z/
  
  require 'sidekiq/testing'
  Sidekiq::Testing.inline!

  # Use https and no port so emailed links match the public tunnel (not localhost:3000).
  config.action_mailer.default_url_options = {
    host: ENV.fetch("MAILER_HOST", ENV.fetch("APP_HOST", "mysql-blake-accommodation-clips.trycloudflare.com")),
    protocol: "https"
  }


  #config.hosts << "amank.in.ngrok.io"

  # Settings specified here will take precedence over those in config/application.rb.

  # In the development environment your application's code is reloaded on
  # every request. This slows down response time but is perfect for development
  # since you don't have to restart the web server when you make code changes.
  config.cache_classes = false

  # Do not eager load code on boot.
  config.eager_load = false

  config.action_cable.url = "ws://localhost:8081/cable"
  config.action_cable.disable_request_forgery_protection = true

  # Show full error reports.
  config.consider_all_requests_local = true
  BetterErrors::Middleware.allow_ip! "0.0.0.0/0"

  # Enable/disable caching. By default caching is disabled.
  # Run rails dev:cache to toggle caching.
  if Rails.root.join('tmp', 'caching-dev.txt').exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true

    cache_servers = %W{#{ENV.fetch("REDIS_URL", nil)}}

    config.cache_store = :redis_cache_store, { url: cache_servers,
      connect_timeout:    30,  # Defaults to 20 seconds
      read_timeout:       1,   # Defaults to 1 second
      write_timeout:      1.3, # Defaults to 1 second
      reconnect_attempts: 1,   # Defaults to 0
      error_handler: -> (method:, returning:, exception:) {
        # Report errors to Sentry as warnings
        # Sentry.capture_message(exception, level: :warning,
        #   tags: { method: method, returning: returning }
        # )
      }
    }

    config.public_file_server.headers = {
      'Cache-Control' => "public, max-age=#{2.days.to_i}"
    }
  else
    config.action_controller.perform_caching = false

    config.cache_store = :null_store
  end

  config.force_ssl = true

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = false

  config.action_mailer.perform_caching = false

  config.action_mailer.delivery_method = :letter_opener
  config.action_mailer.perform_deliveries = true

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Highlight code that triggered database queries in logs.
  config.active_record.verbose_query_logs = true

  # Debug mode disables concatenation and preprocessing of assets.
  # This option may cause significant delays in view rendering with a large
  # number of complex assets.
  config.assets.debug = true

  Rails.application.routes.default_url_options[:host] = 'localhost'
  Rails.application.routes.default_url_options[:port] = 3000
  Rails.application.routes.default_url_options[:protocol] = 'http'

  # Suppress logger output for asset requests.
  config.assets.quiet = true

  config.action_controller.asset_host = "https://#{ENV.fetch("APP_HOST", nil)}"

  config.web_socket_server_url = "wss://#{ENV.fetch("APP_HOST", nil)}/cable"

  # Raises error for missing translations.
  # config.action_view.raise_on_missing_translations = true

  # Use an evented file watcher to asynchronously detect changes in source code,
  # routes, locales, etc. This feature depends on the listen gem.
  config.file_watcher = ActiveSupport::EventedFileUpdateChecker

end
