require 'uri'
require 'net/http'

module NetworkJobs
    class ZipcodeRefreshJob < ApplicationJob  

      
        def perform
          url = URI('https://zipdetails.s3.us-east-1.amazonaws.com/allCountries.txt')
          response = Net::HTTP.get(url)

          response.each_line do |line|
                columns = line.split("\t")
                country = columns[0]
                zipcode = columns[1]
                province = columns[3]
                city = columns[5]
                
                # check if the record already exists, using the zipcode as the primary key
                location = Location.find_by(zipcode: zipcode, country:country)
                
                # if it doesn't exist, create a new record with the given values
                if location.nil?
                  Location.create(
                    country: country,
                    zipcode: zipcode,
                    province: province,
                    city: city,
                  )
                # if it exists, update the existing record with the new values
                else
                  location.update(
                    country: country,
                    province: province,
                    city: city,
                  )
                end
              end
        end
    end
end