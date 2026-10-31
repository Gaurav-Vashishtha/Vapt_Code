require 'sidekiq'
require 'sidekiq-unique-jobs'

SidekiqUniqueJobs.configure do |config|
  config.lock_info = true
end


schedule_file = "config/schedule.yml"

# if Rails.env.development?
#   require 'sidekiq/testing'
#   Sidekiq::Testing.inline!
# end

Sidekiq::Options[:cron_poll_interval] = 1

Sidekiq.configure_server do |config|
  config.redis = {
    url: ENV.fetch("REDIS_URL", nil),
    ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
  }


  #config.redis = { url: ENV["REDIS_URL"], driver: :hiredis }

  # accepts :expiration (optional)
  # Sidekiq::Status.configure_server_middleware config, expiration: 2.days

  # accepts :expiration (optional)
  # Sidekiq::Status.configure_client_middleware config, expiration: 2.days

end

Sidekiq.configure_client do |config|
  config.redis = {
      url: ENV.fetch("REDIS_URL", nil),
      ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
  }
  # accepts :expiration (optional)
  # Sidekiq::Status.configure_client_middleware config, expiration: 2.days
end

if File.exist?(schedule_file) && Sidekiq.server?
  Sidekiq::Cron::Job.load_from_hash YAML.load_file(schedule_file)
end


# Sidekiq::Throttled.setup!