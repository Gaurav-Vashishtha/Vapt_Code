module PricingJobs
  class CountrywisePriceJob < ApplicationJob
    def perform(*_args)
      update_sms_prices
      update_whatsapp_prices
    end

    private

    # WhatsApp utility / marketing rates from Meta's INR rate card × markup
    # (MetaWhatsappRateCardService). Independent of the SMS update above.
    def update_whatsapp_prices
      result = MetaWhatsappRateCardService.call
      changed = result.changes.first(25).map do |c|
        "#{c.country_code} (#{c.market}): utility #{c.utility_was.inspect}→#{c.utility}, marketing #{c.marketing_was.inspect}→#{c.marketing}"
      end
      SlackNotifier::CLIENT.ping(
        text: "WhatsApp rate card sync (#{Rails.env}): Meta INR card effective #{result.effective_on}, " \
              "x#{result.markup} at #{result.inr_per_usd} INR/USD — #{result.changes.size} countries updated, " \
              "#{result.unchanged} unchanged, skipped #{result.skipped.uniq.join(',')}" \
              "#{"\n" + changed.join("\n") if changed.any?}#{"\n…" if result.changes.size > 25}"
      )
    rescue StandardError => e
      SlackNotifier::CLIENT.ping(
        text: "WhatsApp rate card sync FAILED (#{Rails.env}) — twilio_pricings left unchanged: #{e.class}: #{e.message}"
      )
    end

    def update_sms_prices
      cheap_countries = {'PH'=>0.09,'IN'=>0.0125,'AE'=>0.18,'AT'=>0.2,'BE'=>0.2,'CL'=>0.12,'DK'=>0.12,'DE'=>0.26,'FI'=>0.18,'GR'=>0.16,'IL'=>0.27,'JP'=>0.15,'MA'=>0.23,'QA'=>0.07,'ES'=>0.13,'UA'=>0.35,'TN'=>0.16,'GB'=>0.10, 'PK'=>0.09,'EG'=>0.09}
      special_countries = ["IT"]
      TwilioPricing.find_each do |pricing|
        next if pricing["country_code"] == "IA"
        pricing.sms_price = TwilioServices::CountryPriceService.call(pricing["country_code"])
        if !cheap_countries[pricing["country_code"]].blank?
          pricing["sms_price"] = cheap_countries[pricing["country_code"]]
        elsif special_countries.include? pricing["country_code"]
          pricing["sms_price"] = (pricing["sms_price"].to_f * 2).round(4)
        else
          pricing["sms_price"] = (pricing["sms_price"].to_f * 2.2).round(4)
        end
        puts "Updating price for #{pricing["country_code"]} to #{pricing["sms_price"]}"
        pricing.save
      end
    rescue StandardError => e
      error_report = ([e.message] + e.backtrace).join($/)
      #   puts 'CountryWisePriceJob Rescue Error: (#{Rails.env}) \n #{error_report}'
      SlackNotifier::CLIENT.ping(
        text: "CountryWisePriceJob Rescue Error: (#{Rails.env}) \n #{error_report}",
      )
    end
  end
end