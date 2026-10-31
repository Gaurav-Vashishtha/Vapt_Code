module ShopifyServices
  class OrderFullGetService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    # params = ShopifyServices::OrderFullGetService.call(
    #   Shop.last,
    #   OrderConfirmation.last
    # )

    def initialize(client, shop, order_id)
      @client = client
      @shop = shop
      @order_id = order_id
    end

    def get_order
      query = @client.parse <<-'GRAPHQL'
        query ($id:ID!){
          order(id:$id){
            id,
            email,
            phone,
            tags,
            paymentGatewayNames,
            customerLocale,
            currencyCode,
            createdAt,
            taxesIncluded,
            customer{
              firstName,
              lastName,
              id,
              email,
              numberOfOrders
            }
            shippingLine{
              discountedPriceSet{
                presentmentMoney{
                  amount
                  currencyCode
                }
                shopMoney{
                  amount
                  currencyCode
                }
              }
              shippingRateHandle
              title
            }
            lineItems (first: 20) {
              edges {
                node {
                  discountedTotalSet{
                    presentmentMoney{
                      amount
                      currencyCode
                    }
                    shopMoney{
                      amount
                      currencyCode
                    }
                  }
                  name
                  requiresShipping
                  originalTotalSet{
                    presentmentMoney{
                      amount
                      currencyCode
                    }
                    shopMoney{
                      amount
                      currencyCode
                    }
                  }
                  variant{
                    id
                  }
                  sku
                  title
                  quantity
                  sku
                  vendor
                  taxLines {
                    rate
                    ratePercentage
                  }
                }
              }
            }
          
            currentTotalPriceSet{
              presentmentMoney{
                amount
                currencyCode
              }
              shopMoney{
                amount
                currencyCode
              }
            }
            billingAddress{
              address1,
              address2,
              city,
              company,
              country,
              countryCodeV2,
              firstName,
              formatted,
              formattedArea,
              lastName,
              latitude,
              longitude,
              name,
              phone,
              province,
              provinceCode,
              zip
            }
            canNotifyCustomer
            cartDiscountAmountSet{
              presentmentMoney{
                amount
                currencyCode
              }
              shopMoney{
                amount
                currencyCode
              }
            }
            
            totalShippingPriceSet{
              shopMoney{
                amount
                currencyCode
              }
            }

            currentSubtotalLineItemsQuantity
            currentSubtotalPriceSet{
              presentmentMoney{
                amount
                currencyCode
              }
              shopMoney{
                amount
                currencyCode
              }
            }
            currentTotalDiscountsSet{
              presentmentMoney{
                amount
                currencyCode
              }
              shopMoney{
                amount
                currencyCode
              }
            }
            currentTaxLines{
              priceSet{
                presentmentMoney{
                  amount
                  currencyCode
                }
                shopMoney{
                  amount
                  currencyCode
                }
              }
              rate
              ratePercentage
              title
            }
            shippingAddress{
              address1,
              address2,
              city,
              company,
              country,
              countryCodeV2,
              firstName,
              formatted,
              formattedArea,
              lastName,
              latitude,
              longitude,
              name,
              phone,
              province,
              provinceCode,
              zip
            }
          }
        }
      GRAPHQL
      variables = {
        'id': "gid://shopify/Order/#{@order_id}"
      }
      resp = @client.query(query, variables: variables)
      return resp
    end

    # Shopify answers a rejected access token with a 401, and graphql-client
    # hands that back as a response whose `data` is nil — so `resp.data.order`
    # used to blow up with "undefined method `order' for nil:NilClass" and kill
    # the calling job. Callers get nil now and decide what to do without it.
    UNAUTHORIZED_PATTERN = /401|unauthorized|access token|invalid api key/i

    def call
      return nil if @order_id.blank?

      shopify_order = fetch_order
      return nil if shopify_order.blank?

      shopify_order.to_h.deep_dup
    end

    private

    def fetch_order
      2.times do |attempt|
        reason = nil
        begin
          resp = get_order
          order = resp&.data&.order
          return order if order.present?

          reason = response_error_text(resp)
        rescue StandardError => e
          reason = "#{e.class}: #{e.message}"
        end

        # Shopify rejected our token (revoked out of band by a reinstall, a
        # scope change or a rotated secret). Rotate it, rebuild the client and
        # try once more. Any other failure — a real query error, a deleted
        # order — is final.
        next if attempt.zero? && unauthorized?(reason) && reconnect!

        report_unreadable(reason)
        return nil
      end
      nil
    end

    def response_error_text(resp)
      return 'empty response' if resp.blank?

      messages = []
      messages.concat(Array(resp.errors&.messages&.values).flatten) if resp.respond_to?(:errors)
      if resp.respond_to?(:data) && resp.data.respond_to?(:errors)
        messages.concat(Array(resp.data.errors&.messages&.values).flatten)
      end
      messages.compact.map(&:to_s).reject(&:blank?).join('; ').presence || 'no order in response'
    rescue StandardError
      'unreadable response'
    end

    def unauthorized?(reason)
      reason.to_s.match?(UNAUTHORIZED_PATTERN)
    end

    # Returns true only when the token was actually rotated and a retry is worth
    # making. Where the offline-token service can't rotate, we still clear the
    # stale metadata so the next embedded app load re-mints it.
    def reconnect!
      svc = ShopifyServices::OfflineTokenService
      unless svc.respond_to?(:recover_from_unauthorized!)
        svc.invalidate!(@shop, failed_token: @shop.shopify_token) if svc.respond_to?(:invalidate!)
        return false
      end

      return false unless svc.recover_from_unauthorized!(@shop, failed_token: @shop.shopify_token)

      @shop.init_session
      @client = ShopifyAPI::GraphQL.client
      true
    rescue StandardError => e
      Rails.logger.warn("[order_full_get] token rotation failed shop=#{@shop&.shopify_domain}: #{e.class}: #{e.message}")
      false
    end

    def report_unreadable(reason)
      Rails.logger.warn(
        "[order_full_get] shop=#{@shop&.shopify_domain} order=#{@order_id} unreadable (#{reason})"
      )
      if unauthorized?(reason)
        # Throttled to once/shop/day — a shop with a dead token fails on every
        # order, and we don't want that in Slack a few hundred times.
        @shop&.notify_token_reauth_needed_once("GraphQL order read rejected (order_id=#{@order_id})")
      else
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n *Error* Unable to get order #{@order_id} for #{@shop&.shopify_domain}: #{reason}"
        )
      end
    rescue StandardError
      nil
    end
  end
end
