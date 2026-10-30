module SidekiqJobs
  class NotificationDeliveryJob
    include Sidekiq::Worker
    sidekiq_options retry: true

    def perform(shop_id, template_name, force = false)
      shop = Shop.find_by(id: shop_id)
      template = NotificationTemplate.find_by(name: template_name)
      return unless shop && template&.active?

      if NotificationLog.where(shop_id:shop.id,template_name:template_name).count>0
        return
      end

      if UnsubscribedEmail.exists?(email: shop.owner_email)
        return
      end

      unless force || still_matches_criteria?(shop, template)
        Rails.logger.info "[Notification] Skipped #{template_name} for shop #{shop.id} — criteria not met"
        return
      end

      variables = build_variables(shop, template_name)
      NotificationMailer.send_dynamic_notification(shop, template_name, variables).deliver_now
    end

  
    def still_matches_criteria?(shop, template)
      params = template.trigger_params.deep_symbolize_keys
      local_time = Time.current.in_time_zone(clean_timezone(shop.owner_timezone))

      case template.trigger_type
      when "no_features_enabled"
          shop.created_at <= local_time - params[:days].days &&
            !shop.has_enabled_any_feature?
      when "billing_not_activated"
          shop.created_at <= local_time - params[:days].days &&
            !shop.billing_activated?
      when "time_after_signup"
        shop.created_at <= local_time - params[:days].days
      when "prepaid_boost_case_study"
        shop.created_at <= local_time - params[:days].days && shop.prepaid_boost_case_study
      when "abandoned_cart_not_enabled"
        shop.created_at <= local_time - params[:days].days &&
          !(shop.abandoned_cart_enabled rescue false)
      else
        true
      end
    end

    def clean_timezone(owner_timezone)
      owner_timezone.to_s.split(' ').last || 'UTC'
    end

    def build_variables(shop, template_name)
      {
        name: shop.shop_owner,
        shopify_domain: shop.shopify_domain,
        tracking_url: Rails.application.routes.url_helpers.track_notification_url(shop.id, template_name),
        crisp_url: shop.crisp_url,
        email: shop.owner_email
      }
    end
  end
end
