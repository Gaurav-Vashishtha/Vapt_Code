source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.2.6'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '~> 7.2.2.1'
# Use postgres as the database for Active Record
gem 'pg', '>= 0.18', '< 2.0'
# Use Puma as the app server
gem 'puma', '~> 6.0'
# Use SCSS for stylesheets
gem 'sass-rails', '>= 6'
# Transpile app-like JavaScript. Read more: https://github.com/rails/webpacker
gem 'webpacker', '~> 5.4'
# Turbolinks makes navigating your web application faster. Read more: https://github.com/turbolinks/turbolinks
gem 'turbolinks', '~> 5'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder', '~> 2.7'
# Use Redis adapter to run Action Cable in production
# gem 'redis', '~> 4.0'
# Use Active Model has_secure_password
# gem 'bcrypt', '~> 3.1.7'
gem 'execjs'
# Use Active Storage variant
# gem 'image_processing', '~> 1.2'
gem 'ruby-vips', '~> 2.2', require: false

gem 'money', '~> 6.13'
gem 'eu_central_bank'
gem 'sidekiq-unique-jobs'
gem 'money-open-exchange-rates'

gem 'bcrypt', '~> 3.1.7'
gem 'jwt', '~> 2.5'



# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', '>= 1.4.2', require: false
gem "administrate"
gem 'rack-cors'
gem 'shopify_app', '=18.1.2'
gem "sentry-ruby"
gem "sentry-rails"
gem 'aws-sdk-rails', '~> 3'
gem 'aws-sdk-s3', '~> 1'
gem 'exception_notification'
gem "slack-notifier"
gem "redis"
# gem 'rails_web_cache'
gem 'httparty'
gem 'pagy', '~> 3.5'
gem 'sidekiq', '~> 7.2.0'
gem "sidekiq-cron", "~> 1.9"
gem 'coffee-rails'
gem 'scout_apm'
gem 'twilio-ruby', '~> 5.53.0'
gem 'active_model_otp'
gem 'phonelib', '>=0.7.3'
gem 'i18n-js', '~> 3.0', '>= 3.0.2'
gem 'bitly'
gem "roo", "~> 2.8.0"
gem "caxlsx"
gem 'foreman'
# gem 'newrelic_rpm'
gem 'rails_autoscale_agent'
gem 'active_model_cachers'
gem 'rack-attack'
gem 'razorpay'
gem "puma_worker_killer"
gem 'platform-api'


group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  gem 'dotenv-rails'
end

group :development do
  # Access an interactive console on exception pages or by calling 'console' anywhere in the code.
  gem 'web-console', '>= 3.3.0'
  gem 'listen', '~> 3.2'
  gem "better_errors"
  gem "binding_of_caller"
  gem "letter_opener"
  gem 'letter_opener_web', '~> 1.0'
  gem 'pry-rails'
end

group :test do
  # Adds support for Capybara system testing and selenium driver
  gem 'capybara', '>= 2.15'
  gem 'selenium-webdriver'
  # Easy installation and use of web drivers to run system tests with browsers
  gem 'webdrivers'
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]


gem 'graphiql-rails', group: :development