module ShopifyJobs
  class PartialProductCleanupJob < ApplicationJob
    
    def perform
      puts 'Partial Product job started'
      
      # Fetch partial product mappings older than 1.5 hour
      partial_product_mappings = PartialProductMapping.where(is_deleted:false).where('created_at < ?', 90.minutes.ago)

      partial_product_mappings.each do |partial_product_mapping|
        shop = Shop.find_by(shopify_domain: partial_product_mapping.shopify_domain) # Corrected syntax error
        
        if shop.present? # Use `present?` instead of `blank?`
          begin
            shop.init_session
            # Extract product ID and find the respective product
            resp = ShopifyServices::ProductDeleteService.call(shop, partial_product_mapping.partial_product_id)  
            puts "Product delete response #{resp.inspect} "
            partial_product_mapping.update(is_deleted:true)
            
            
          rescue ActiveResource::ResourceNotFound => e
            puts "Error: Product not found with ID ##{product_id}. Exception: #{e.message} #{e.backtrace}"
            partial_product_mapping.update(is_deleted:true)
          rescue => e
            puts "An unexpected error occurred for shop #{shop.shopify_domain}. Exception: #{e.message} #{e.backtrace}"
            partial_product_mapping.update(is_deleted:true)
          end
        else
          puts "Shop with domain #{partial_product_mapping.shopify_domain} not found."
          partial_product_mapping.update(is_deleted:true)
        end
      end
      
      puts 'Partial Product job completed'
    end
  end
end
