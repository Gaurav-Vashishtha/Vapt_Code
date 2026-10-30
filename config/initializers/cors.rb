Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins do |source, _env|
      true
    end
    resource '*', headers: :any, methods: [:get, :post, :delete, :options], credentials: true
  end
end
