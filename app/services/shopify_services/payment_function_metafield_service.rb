module ShopifyServices
  class PaymentFunctionMetafieldService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    # params = ShopifyServices::PaymentFunctionMetafieldService.call(
    #   Shop.last, "gid://shopify/PaymentCustomization/11731250", 'Cash on Delivery', 100.0,250.0
    # )

    def initialize(client, shop, owner_id, payment_method_name)
      @client = client
      @shop = shop
      @owner_id = owner_id
      @payment_method_name = payment_method_name
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
    meta_value = {
      paymentMethodName: setting.payment_method_name.blank? ? 'Cash on Delivery' : setting.payment_method_name,
      minCartTotal: setting.min_cart_total.blank? ? 0 : setting.min_cart_total ,
      maxCartTotal: setting.max_cart_total.blank? ? 999999 : setting.max_cart_total ,
      hideDeliveryMethod: setting.hide_delivery_method.blank? ? '' : setting.hide_delivery_method ,
      selectedCountries: setting.selected_countries.blank? ? '' : setting.selected_countries ,
      selectedZips: setting.selected_zips.blank? ? '' : setting.selected_zips ,
      selectedProductIds: setting.selected_product_ids.blank? ? '' : setting.selected_product_ids ,
      enablePreOrderOtp: setting.enable_pre_order_otp.blank? ? 'false' : setting.enable_pre_order_otp.to_s ,
      phoneNumbers:  setting.phone_numbers.blank? ? '' : setting.phone_numbers ,
      excludedZips: setting.excluded_zips.blank? ? '' : setting.excluded_zips, 
      codPaymentName: setting.cod_fee_enabled==true ? setting.cod_label : '',
      excludedShippingMethods: setting.excluded_shipping_methods.blank? ? '' : setting.excluded_shipping_methods, 
      showProvinces: setting.show_provinces.blank? ? '' : setting.show_provinces, 
      hideProvinces: setting.hide_provinces.blank? ? '' : setting.hide_provinces, 
      debug: setting.debug.blank? ? false : setting.debug, 
      codFeeShippingKeyword: setting.cod_fee_shipping_keyword.blank? ? '' : setting.cod_fee_shipping_keyword, 
      enableShippingCodFees: setting.enable_shipping_cod_fees.blank? ? 'false' : setting.enable_shipping_cod_fees.to_s, 
      hideProductVariantIds: setting.hide_product_variant_ids.blank? ? '' : setting.hide_product_variant_ids.to_s, 
      lockPaidFeature: setting.lock_paid_feature.blank? ? false : setting.lock_paid_feature,
      showProductIds: setting.show_product_ids.blank? ? '' : setting.show_product_ids, 
      hideForUnverifiedOrders: setting.hide_for_unverified_orders.presence || false,
      preIsLoginEnabled: setting.pre_is_login_enabled? ? false :  setting.pre_is_login_enabled,
      partialPaymentEnabled: setting.partial_payment_enabled? ? true :  setting.partial_payment_enabled,
      hideDiscountTotal: setting.hide_discount_total.blank? ? 0 :  setting.hide_discount_total,
      emailAddresses:  setting.email_addresses.blank? ? '' : setting.email_addresses,
      hideGiftCards: setting.hide_gift_cards? ? true :  false,
      hideVendors:  setting.hide_vendors.blank? ? '' : setting.hide_vendors,
      showVendors:  setting.show_vendors.blank? ? '' : setting.show_vendors,
      partialShippingKeyword: setting.partial_shipping_keyword.blank? ? '' : setting.partial_shipping_keyword, 
      partialHidePaymentMethods: @shop.additional_setting&.third_party_hidden_payment_methods(:hide_on_partial).to_s,
      prepaidHidePaymentMethods: @shop.additional_setting&.third_party_hidden_payment_methods(:hide_on_prepaid).to_s,
      collectionIds: collectionIds.present? ? collectionIds.split(',').map { |id| "gid://shopify/Collection/#{id.strip}" } : [],
      isHideCollectionId: isHideCollectionId,
      tagList: ["abctest", "vip", "wholesale"]
    }

      variables = {
        metafields: [
          {
           ownerId: @owner_id,
           namespace: "payment-customization",
           key: "function-configuration",
           value: meta_value.to_json,
           type: "json"
          }
        ] 
      }
      resp = @client.query(query, variables: variables)
      puts "value written #{meta_value.to_json}"
      return resp
    end

    def call
      resp = set_metafields
      if !resp&.data&.metafields_set&.metafields&.first&.id.blank?
        return resp&.data&.metafields_set&.metafields&.first&.id
      else
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n  *Unable to create Metafields function for shop #{@shop.shopify_domain} resp #{resp.inspect}"
        )
        return nil
      end
      puts resp
    end
  end
end
