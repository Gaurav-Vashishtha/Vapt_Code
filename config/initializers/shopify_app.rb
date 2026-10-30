ShopifyApp.configure do |config|
  config.application_name = 'COD Confirmation'
  config.old_secret = ''
  scopes = %w[
    read_checkouts
    read_orders
    read_order_edits
    read_products
    read_script_tags
    unauthenticated_read_checkouts
    unauthenticated_write_checkouts
    unauthenticated_read_customers
    unauthenticated_write_customers
    write_checkouts
    write_orders
    write_order_edits
    write_products
    write_script_tags
    read_draft_orders
    write_draft_orders
    read_customers
    write_customers
    read_content
    write_content
    read_payment_customizations
    write_payment_customizations
    read_translations
    read_delivery_customizations
    write_delivery_customizations
    unauthenticated_read_customer_tags
    unauthenticated_read_metaobjects
    unauthenticated_read_product_inventory
    unauthenticated_read_product_listings
    unauthenticated_read_product_pickup_locations
    unauthenticated_read_product_tags
    unauthenticated_read_selling_plans
    write_price_rules
    read_price_rules
    read_themes
    read_locations
    write_locations
    write_inventory
    read_inventory
    read_discounts
    write_discounts
    write_cart_transforms
    write_pixels
    read_customer_events
    read_cart_transforms
    ]
  if Rails.env.production?
    scopes = scopes.push('read_all_orders')
  end
  config.scope = scopes.join(', ')

  # Consult this page for more scope options:
  # https://help.shopify.com/en/api/getting-started/authentication/oauth/scopes
  config.embedded_app = true
  # Runs after every successful OAuth (install / reinstall / scope change).
  # Required for reinstalls where Setting already exists, so its on:create hook won't fire.
  # NOTE: pass the job class as a STRING — initializers run before Zeitwerk autoloads
  # `app/workers`, so a bare constant raises NameError at boot. Gem constantizes at enqueue time.
  #config.after_authenticate_job = { job: "ShopifyJobs::AfterAuthenticatePixelSyncJob", inline: false }
  config.api_version = '2025-07'
  config.shop_session_repository = 'Shop'
  config.allow_jwt_authentication = true
  config.allow_cookie_authentication = false
  # config.scripttags = [{
  #   event: 'onload',
  #   display_scope: 'order_status',
  #   cache: Rails.env.production?,
  #   src: ->(_domain) { "https://#{ENV['APP_HOST']}/script.js" }
  # }]
  config.webhooks = [{
    topic: 'app/uninstalled',
    address: ENV['AWS_EVENT_BRIDGE_ARN'],
    format: 'json'
  },
  {
    topic: 'orders/create',
    address: ENV['AWS_ORDER_CREATE_EVENT_BRIDGE_ARN'],
    format: 'json'
  },
  {
  topic: 'customers/create',
  address: ENV['AWS_EVENT_BRIDGE_ARN'],
  format: 'json'
  }
]
  config.api_key = ENV['SHOPIFY_API_KEY']
  config.secret = ENV['SHOPIFY_API_SECRET']
  if defined? Rails::Server
    raise('Missing SHOPIFY_API_KEY. See https://github.com/Shopify/shopify_app#api-keys') unless config.api_key
    raise('Missing SHOPIFY_API_SECRET. See https://github.com/Shopify/shopify_app#api-keys') unless config.secret
  end
end
ShopifyAPI::Base.api_version = '2025-07'

# ShopifyApp::Utils.fetch_known_api_versions                        # Uncomment to fetch known api versions from shopify servers on boot
# ShopifyAPI::ApiVersion.version_lookup_mode = :raise_on_unknown    # Uncomment to raise an error if attempting to use an api version that was not previously known
