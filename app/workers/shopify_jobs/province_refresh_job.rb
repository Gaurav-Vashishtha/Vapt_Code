module ShopifyJobs
  class ProvinceRefreshJob < ApplicationJob
    # ShopifyJobs::ProvinceRefreshJob.perform_async
    def perform
      puts 'Province job started'
      Shop.last.init_session
      countries = ShopifyAPI::Country.all
      countries.each do|country|
        if !country.provinces.blank?
          country.provinces.each do|province|
            province = Province.find_or_initialize_by(country_code:country.code,country_name:country.name,
            country_id:country.id,province_code:province.code,province_id:province.id,province_name:province.name )
            if !province.save
              puts 'Error saving province'
            end
          end
        end
      end
    end
  end
end
