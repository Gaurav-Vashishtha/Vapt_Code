require 'roo'
namespace :twilio do
  desc "Import data from spreadsheet"
  task pricing: :environment do
    puts 'Importing Data'
    cheap_countries = ['IN']
    data = Roo::Spreadsheet.open('lib/sms-pricing.csv') # open spreadsheet
    headers = data.row(1) # get header row
    data.each_with_index do |row, idx|
      next if idx == 0 # skip header row
      # create hash from headers and cells
      sms_data = Hash[[headers, row].transpose]
      sms_data.delete('Description')
      sms_data['country_code'] = sms_data.delete 'ISO'
      sms_data['country'] = sms_data.delete 'Country'
      sms_data['sms_price'] = sms_data.delete 'Price / msg'
      if cheap_countries.include? sms_data['country_code']
        sms_data['sms_price'] = (sms_data['sms_price'].to_f * 1.5).round(4)
        puts "cheap country: #{sms_data['country_code']} price: #{sms_data['sms_price']}"
      else
        sms_data['sms_price'] = (sms_data['sms_price'].to_f * 3).round(4)
      end
      # next if pricing exists
      if TwilioPricing.exists?(country_code: sms_data['country_code'])
        pricing = TwilioPricing.find_by(country_code: sms_data['country_code'])
        if sms_data['sms_price'].to_f > pricing.sms_price.to_f
          pricing.update(sms_data)
         puts "Updated with higher pricing for country_code #{pricing.country_code}"
        end
        next
      end
      pricing = TwilioPricing.new(sms_data)
      puts "Saving TwilioPricing with country_code '#{pricing.country_code}'"
      pricing.save!
    end
  end
end
