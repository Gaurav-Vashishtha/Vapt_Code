module ShopifyServices
  class CheckoutProfileGetService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    def initialize(client, shop)
      @client = client
      @shop = shop
    end

    def get_checkout_profile
      query = @client.parse <<-'GRAPHQL'
      {
        checkoutProfiles(first:100) {
          edges {
            node{
              id
              isPublished
              typOspPagesActive
            }
          }
          # CheckoutProfile fields
        }
      }
      GRAPHQL
      
      resp = @client.query(query)
      return resp
    end


    def call
      begin
      checkout_profiles = get_checkout_profile
      if !checkout_profiles.blank?
        checkout_profiles = checkout_profiles && checkout_profiles.data && checkout_profiles.data.checkout_profiles && checkout_profiles.data.checkout_profiles.edges 
        checkout_profiles.each do |node|
          node = node.node
          if node && node.is_published
            puts node.id

            return {id: node.id.gsub("gid://shopify/CheckoutProfile/",""), typOspPagesActive: node.typ_osp_pages_active}
          end
        end
      else
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n *Error* Unable to get checkoutProfile for shop #{shop.id}"
        )
        return false
      end
      rescue Exception => e
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n *Error* Unable to get checkoutProfile for shop #{shop.id} #{e.backtrace}"
        )
        return false
      end
    end
  end
end
