module ShopifyServices
    class CustomerSingleDataSaveService < ShopifyServices::GraphqlService
      attr_reader :shop, :client

      # ShopifyServices::CustomerDataSaveService.call(@shop,customers)
  
      def initialize(client, shop, customer)
        @client = client
        @shop = shop
        @customer = customer
      end

      def get_unique_phone_numbers(customer)
        phones = [customer['phone']]
        phones += customer['addresses'].map { |address| address['phone'] }
        if !phones.blank? && (phones.count > 0)
          phones = (phones.reject { |c| c.blank?}).uniq
        end
        puts "Phones extracted #{phones.to_s}"
        process_phone_numbers(customer, phones)
      rescue StandardError => e
        puts "Error while extracting and processing phone numbers: #{e.message}"
      end


      def process_phone_numbers(customer, phones)
        return [] if phones.blank?
      
        default_country_code = 'IN'
        country_code = customer.dig('default_address', 'country_code_v2') || default_country_code
        final_phones = Array.new(phones.length)
      
        final_phones = phones.map do |phone|
          begin
            Phonelib.parse(phone, country_code).to_s
          rescue Phonelib::InvalidNumberError, Phonelib::NumberParseException, Phonelib::NotSupportedCountryError => e
            phone.gsub(' ', '')
          end
        end
      
        return final_phones
      rescue StandardError => e
        puts "Error while processing phone numbers: #{e.message}"
        return []
      end
  
      # Postgres text/varchar columns reject strings containing U+0000 (null byte).
      # Shopify occasionally returns address fields with embedded null bytes; strip them
      # before persisting so a single bad row doesn't blow up the entire pull.
      def self.scrub_null_bytes(value)
        case value
        when String then value.delete("\x00")
        when Hash   then value.transform_values { |v| scrub_null_bytes(v) }
        when Array  then value.map { |v| scrub_null_bytes(v) }
        else value
        end
      end

      def call
        customer = self.class.scrub_null_bytes(@customer)
        if !@customer.blank?
             phones = get_unique_phone_numbers(customer)
             addresses = customer['addresses']
             #Iterate over phone numbers and addresses create all combination of it.
             if phones.blank?
              puts "No phones for #{customer['id']}"
              return
             end
             phones.each do |phone|
                db_customer = Customer.find_or_initialize_by(phone:phone)
                customer_update = db_customer.update(
                  email: customer['email'] || db_customer.email,
                  first_name: customer['firstName'] || db_customer.first_name,
                  last_name: customer['lastName'] || db_customer.last_name,
                  tags: customer['tags'] || db_customer.tags,
                  currency: customer.dig('amountSpent','currencyCode')  || db_customer.currency
                )
                
                puts "customer_update#{customer_update}"
                db_customer_shop_mapping = CustomerShopMapping.find_or_initialize_by(customer_id: db_customer.id, 
                shopify_domain: @shop.shopify_domain)
                customer_shop_mapping_update = db_customer_shop_mapping.update(
                  order_value: customer.dig('amountSpent','amount') || customer.dig('totalSpent') ||  db_customer_shop_mapping.order_value,
                  predicted_spend_tier: customer.dig('statistics','predictedSpendTier') || db_customer_shop_mapping.predicted_spend_tier,
                  lifetime_duration: customer['lifetimeDuration'] || db_customer_shop_mapping.lifetime_duration,
                  order_count: customer['numberOfOrders'] || customer.dig('ordersCount') || db_customer_shop_mapping.order_count,
                  verified_email: customer['verifiedEmail'].nil? ? db_customer_shop_mapping.verified_email : customer['verifiedEmail']
                )
                puts "customer_shop_mapping_update#{customer_shop_mapping_update}"
                if customer_update
                  addresses.each do |address|
                    db_customer_address = CustomerAddress.find_or_initialize_by(shopify_id:address['id'],customer_id: db_customer.id)
                    if !(address['address1'].blank? && address['address2'].blank? && db_customer_address.address1.blank? && db_customer_address.address2.blank?) #If everything is blank then skip it.
                      db_customer_address.update(
                        first_name: address['firstName'] || db_customer_address.first_name,
                        last_name: address['lastName'] || db_customer_address.last_name,
                        company: address['company'] || db_customer_address.company,
                        address1: address['address1'] || db_customer_address.address1,
                        address2: address['address2'] || db_customer_address.address2,
                        city: address['city'] || db_customer_address.city,
                        province: address['province'] || db_customer_address.province,
                        country: address['country'] || db_customer_address.country,
                        zip: address['zip'] || db_customer_address.zip,
                        phone: address['phone'] || db_customer_address.phone,
                        province_code: address['provinceCode'] || db_customer_address.province_code,
                        country_code: address['countryCodeV2'] || db_customer_address.country_code,
                        country_name: address['countryName'] || db_customer_address.country_name,
                        formatted: address['formatted'] || db_customer_address.formatted,
                        formatted_area: address['formattedArea'] || db_customer_address.formatted_area,
                        latitude: address['latitude'] || db_customer_address.latitude,
                        longitude: address['longitude'] || db_customer_address.longitude,
                        coordinates_validated: address['coordinatesValidated'] || db_customer_address.coordinates_validated,
                        country_code_v2: address['countryCodeV2'] || db_customer_address.country_code_v2,
                        default: address['default'] || db_customer_address.default
                      )
                    end
                  end
                end
             end
        else
          puts 'No customers to process'
        end

      end
    end
  end