module ShopifyServices
  class DeliveryFunctionMetafieldService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    # params = ShopifyServices::PaymentFunctionMetafieldService.call(
    #   Shop.last, "gid://shopify/PaymentCustomization/11731250", 'Cash on Delivery', 100.0,250.0
    # )

    def initialize(client, shop, owner_id)
      @client = client
      @shop = shop
      @owner_id = owner_id
    end

    def set_metafields
      query = @client.parse <<-'GRAPHQL'
        mutation ($metafields: [MetafieldsSetInput!]!) {
          metafieldsSet(metafields: $metafields) {
            metafields {
              id
            }
            userErrors {
              message
            }
          }
        }
      GRAPHQL

      setting = @shop.setting
      
      isHideCollectionId = nil
      collectionIds = []
      
      if setting.excluded_collection_ids.present?
        isHideCollectionId = true
        collectionIds = setting.excluded_collection_ids
      elsif setting.selected_collection_ids.present?
        isHideCollectionId = false
        collectionIds = setting.selected_collection_ids
      end   

      rules_active = setting.hide_shipping_method? || setting.partial_shipping_keyword.present?

      default_meta = {
        paymentMethodName: '',
        minCartTotal: 0,
        maxCartTotal: 9999999,
        hideDeliveryMethod: '',
        selectedCountries: '',
        selectedZips: '',
        selectedProductIds: '',
        enablePreOrderOtp: 'false',
        phoneNumbers: '',
        excludedZips: '',
        codPaymentName: '',
        excludedShippingMethods: '',
        showProvinces: '',
        hideProvinces: '',
        debug: false,
        codFeeShippingKeyword: setting.cod_fee_shipping_keyword.presence || '',
        codOnlyShippingKeyword: setting.cod_only_shipping_keyword.presence || '',
        enableShippingCodFees: 'false',
        hideProductVariantIds: '',
        lockPaidFeature: false,
        showProductIds: '',
        hideShippingMethod: false,
        hideForUnverifiedOrders: false,
        preIsLoginEnabled: false,
        partialPaymentEnabled: false,
        hideDiscountTotal: 0,
        emailAddresses: '',
        hideGiftCards: false,
        hideVendors: '',
        showVendors: '',
        partialShippingKeyword: '',
        collectionIds: [],
        isHideCollectionId: nil,
        tagList: []
      }

      active_meta = {
        paymentMethodName: setting.payment_method_name.presence || 'Cash on Delivery',
        minCartTotal: setting.min_cart_total.presence || 0,
        maxCartTotal: setting.max_cart_total.presence || 999999,
        hideDeliveryMethod: setting.hide_delivery_method.presence || '',
        selectedCountries: setting.selected_countries.presence || '',
        selectedZips: setting.selected_zips.presence || '',
        selectedProductIds: setting.selected_product_ids.presence || '',
        enablePreOrderOtp: setting.enable_pre_order_otp.to_s.presence || 'false',
        phoneNumbers: setting.phone_numbers.presence || '',
        excludedZips: setting.excluded_zips.presence || '',
        codPaymentName: setting.cod_fee_enabled ? setting.cod_label : '',
        excludedShippingMethods: setting.excluded_shipping_methods.presence || '',
        showProvinces: setting.show_provinces.presence || '',
        hideProvinces: setting.hide_provinces.presence || '',
        debug: setting.debug.presence || false,
        codFeeShippingKeyword: setting.cod_fee_shipping_keyword.presence || '',
        codOnlyShippingKeyword: setting.cod_only_shipping_keyword.presence || '',
        enableShippingCodFees: setting.enable_shipping_cod_fees.to_s.presence || 'false',
        hideProductVariantIds: setting.hide_product_variant_ids.to_s.presence || '',
        lockPaidFeature: setting.lock_paid_feature.presence || false,
        showProductIds: setting.show_product_ids.presence || '',
        hideShippingMethod: setting.hide_shipping_method.presence || false,
        hideForUnverifiedOrders: setting.hide_for_unverified_orders.presence || false,
        preIsLoginEnabled: setting.pre_is_login_enabled.presence || false,
        partialPaymentEnabled: setting.partial_payment_enabled.presence || false,
        hideDiscountTotal: setting.hide_discount_total.presence || 0,
        emailAddresses: setting.email_addresses.presence || '',
        hideGiftCards: setting.hide_gift_cards.presence || false,
        hideVendors: setting.hide_vendors.presence || '',
        showVendors: setting.show_vendors.presence || '',
        partialShippingKeyword: setting.partial_shipping_keyword.presence || '',
        collectionIds: collectionIds.present? ? collectionIds.split(',').map { |id| "gid://shopify/Collection/#{id.strip}" } : [],
        isHideCollectionId: isHideCollectionId,
        tagList: ["abctest", "vip", "wholesale"]
      }

      meta_value = rules_active ? active_meta : default_meta

      variables = {
        metafields: [
          {
            ownerId: @owner_id,
            namespace: "delivery-customization",
            key: "function-configuration",
            value: meta_value.to_json,
            type: "json"
          }
        ]
      }

      resp = @client.query(query, variables: variables)
      puts "value written #{meta_value.to_json}"
      resp
    end

    def call
      resp = set_metafields
      if !resp&.data&.metafields_set&.metafields&.first&.id.blank?
        return resp.data.metafields_set.metafields.first.id
      else
        SlackNotifyJob.perform_async(
          ":rage: (#{Rails.env})\n  *Unable to create Metafields function for shop #{@shop.shopify_domain} resp #{resp&.data&.metafields_set&.user_errors}"
        )
        return nil
      end
    end
  end
end
