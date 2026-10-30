module PricingJobs
  class EasysellUsageJob < ApplicationJob
    sidekiq_options queue: "administration"
    # If charge not available in hash
    def perform(*_args)
      usage_count = TwilioLog.where(shop_id:94231).size
      usage_count = (ENV['EASYSELL_MULTIPLIER'].to_f * usage_count).to_i 
      SlackNotifier::CLIENT.ping(
        text: ":heart: EasySell Usage Count (#{Rails.env}) -  #{usage_count}",
      )
      WelcomeMailer.easy_sell_usage_count('adbhatia1989@gmail.com,ayoub.bougsid@gmail.com',usage_count).deliver_later
    end
  end
end