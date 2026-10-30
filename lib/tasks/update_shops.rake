namespace :update_shops do
  desc "Additional fields in shops."
  task :run, [] => :environment do |t, args|
    Shop.all.each do |shop|
      shop.init_session
      api_shop_data = ShopifyAPI::Shop.current
      shop.update(
        country_code: api_shop_data.country_code,
        money_format: api_shop_data.money_format,
        currency: api_shop_data.currency,
      )
      puts "Updated shop #{shop.shopify_domain}"
    end
  end
end