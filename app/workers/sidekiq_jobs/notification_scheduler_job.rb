module SidekiqJobs

  class NotificationSchedulerJob
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform
      NotificationTemplate.where(active: true).find_each do |template|
        params = template.trigger_params.deep_symbolize_keys
        eligible_time = Time.current - params[:days].days

        Shop.where("created_at <= ?", eligible_time).where("id > ?", 30000).find_each do |shop|

          next if shop.customer_email.blank? || UnsubscribedEmail.exists?(email: shop.owner_email)

          puts "Trying matching criteria for Shop #{shop.id}"
          local_time = Time.current.in_time_zone(clean_timezone(shop.owner_timezone))

          next if NotificationLog.exists?(
            shop_id: shop.id,
            template_name: template.name
          )

          next unless match_criteria?(template.trigger_type, params, shop, local_time)

          delivery_time = local_time.change(hour: params[:hour] || 10)

          SidekiqJobs::NotificationDeliveryJob.perform_at(delivery_time, shop.id, template.name)

          NotificationLog.create!(
            shop_id: shop.id,
            template_name: template.name,
            scheduled_at: delivery_time
          )
        end
      end
    end

  
      def clean_timezone(owner_timezone)
        zone = owner_timezone.to_s.split(' ').last
        return 'Asia/Kolkata' if zone.blank?
      
        # Validate with ActiveSupport::TimeZone
        ActiveSupport::TimeZone[zone] ? zone : 'Asia/Kolkata'
      rescue
        'Asia/Kolkata'
      end

    def match_criteria?(type, params, shop, time)
      days_since_signup = (time.to_date - shop.created_at.to_date).to_i

      case type
      when "time_after_signup"
        days_since_signup >= params[:days].to_i
      when "no_features_enabled"
        days_since_signup >= params[:days].to_i && !shop.has_enabled_any_feature?

      when "billing_not_activated"
        days_since_signup == params[:days].to_i && !shop.billing_activated?

      when "prepaid_boost_case_study"
        days_since_signup >= params[:days].to_i && shop.prepaid_boost_case_study
      when "abandoned_cart_not_enabled"
        shop.created_at <= time - params[:days].days &&
          !(shop.abandoned_cart_enabled rescue false)
      else
        false
      end
    end
  end
end