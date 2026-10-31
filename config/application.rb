require_relative 'boot'
require_relative '../app/middleware/redirect_middleware'



require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)



module CodConfirm
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.middleware.use RedirectMiddleware
    config.load_defaults 6.0
    # config.middleware.use I18n::JS::Middleware
    config.middleware.insert_after ActionDispatch::Static, Rack::Deflater
    config.active_job.queue_adapter = :sidekiq

    if ENV.fetch("DB_ENCRYPTION_PRIMARY_KEY", nil).present? &&
       ENV.fetch("DB_ENCRYPTION_DETERMINISTIC_KEY", nil).present? &&
       ENV.fetch("DB_ENCRYPTION_KEY_DERIVATION_SALT", nil).present?
      config.active_record.encryption.primary_key = ENV.fetch("DB_ENCRYPTION_PRIMARY_KEY", nil)
      config.active_record.encryption.deterministic_key = ENV.fetch("DB_ENCRYPTION_DETERMINISTIC_KEY", nil)
      config.active_record.encryption.key_derivation_salt = ENV.fetch("DB_ENCRYPTION_KEY_DERIVATION_SALT", nil)
    end

    config.before_initialize do
      if Psych::VERSION >= '4.0'
        YAML.singleton_class.prepend(Module.new do
          def safe_load(yaml, permitted_classes: [], permitted_symbols: [], aliases: false, **kwargs)
            super(yaml, permitted_classes: permitted_classes, permitted_symbols: permitted_symbols, aliases: true, **kwargs)
          end
        end)
      end
    end

    # config.assets.configure do |env|
    #   env.export_concurrent = false
    # end
    
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
  end
end
