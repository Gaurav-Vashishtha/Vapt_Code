namespace :shopify do
  desc 'Get Products from shopify.'
  task :products_get, [:shop_id, :filters] => :environment do |t, args|
    # filters = Rack::Utils.parse_nested_query(args[:filters])
    filters = {}.to_json
    ENV['SHOPIFY_PRODUCTS_GET_JOB'].constantize.perform_async(
      args[:shop_id], filters
    )
  end

  desc 'Post products to shopify. rake shopify:products_post\[1,"2 3 4"\]'
  task :products_post, [:shop_id, :product_ids] => :environment do |t, args|
    ShopifyJobs::ProductsPostJob.perform_async(
      args[:shop_id], args[:product_ids].split(' ')
    )
  end

  desc 'Get Products from shopify and import them'
  task :products_import, [:shop_id] => :environment do |t, args|
    ShopifyJobs::ProductsImportJob.perform_async(
      args[:shop_id]
    )
  end



end
