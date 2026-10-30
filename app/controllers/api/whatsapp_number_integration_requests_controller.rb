# app/controllers/api/whatsapp_number_integration_requests_controller.rb
class Api::WhatsappNumberIntegrationRequestsController < AuthenticatedController
  before_action :set_shop

  def create
    current_shop = @shop
    setting = current_shop.setting
    
    # Check rate limiting (similar to callback requests)
    if setting.last_whatsapp_integration_request_at.present? &&
       setting.last_whatsapp_integration_request_at > 24.hours.ago
      
      time_remaining = 24.hours - (Time.current - setting.last_whatsapp_integration_request_at)
      hours_remaining = (time_remaining / 1.hour).ceil
      
      return render json: {
        error: 'rate_limited',
        message: I18n.t('whatsapp_integration.rate_limited', hours: hours_remaining),
        next_available_at: setting.last_whatsapp_integration_request_at + 24.hours,
        hours_remaining: hours_remaining
      }, status: :too_many_requests
    end
    
    integration_request = WhatsappNumberIntegrationRequest.new(
      integration_params.merge(
        shop_domain: current_shop.shopify_domain,
        status: 'submitted'
      )
    )
    
    if integration_request.save
      # Update setting with last request time
      setting.update(
        last_whatsapp_integration_request_at: Time.current,
        whatsapp_integration_requests_count: (setting.whatsapp_integration_requests_count || 0) + 1
      )
      
      # Send emails
      WhatsappNumberIntegrationMailer.notify_approvers(integration_request.id).deliver_later
      WhatsappNumberIntegrationMailer.send_acknowledgment(integration_request.id).deliver_later
      
      render json: {
        success: true,
        message: I18n.t('whatsapp_integration.success'),
        integration_request: integration_request,
        next_available_at: Time.current + 24.hours
      }
    else
      render json: {
        error: 'validation_failed',
        errors: integration_request.errors.full_messages
      }, status: :unprocessable_entity
    end
  end
  
  def check_availability
    current_shop = @shop
    setting = current_shop.setting
    
    can_request = setting.last_whatsapp_integration_request_at.nil? ||
                  setting.last_whatsapp_integration_request_at <= 24.hours.ago
    
    render json: {
      can_request: can_request,
      last_request_at: setting.last_whatsapp_integration_request_at,
      next_available_at: setting.last_whatsapp_integration_request_at ? 
                         setting.last_whatsapp_integration_request_at + 24.hours : nil
    }
  end

  def current_status
    current_shop = @shop
    latest_request = WhatsappNumberIntegrationRequest
      .where(shop_domain: current_shop.shopify_domain)
      .order(created_at: :desc)
      .first
    
    if latest_request
      # Can submit new request only if status is 'rejected' or no request exists
      # Treat 'pending' and 'submitted' as the same - both mean request is in progress
      can_submit_new = latest_request.status == 'rejected'
      
      # Normalize status: 'submitted' is same as 'pending'
      normalized_status = latest_request.status == 'submitted' ? 'pending' : latest_request.status
      
      render json: {
        has_request: true,
        status: normalized_status,
        can_submit_new: can_submit_new,
        request: {
          id: latest_request.id,
          email: latest_request.email,
          phone_number: latest_request.phone_number,
          preferred_time: latest_request.preferred_time,
          status: normalized_status,
          created_at: latest_request.created_at
        }
      }
    else
      render json: {
        has_request: false,
        status: nil,
        can_submit_new: true
      }
    end
  end
  
  private
  
  def integration_params
    params.require(:whatsapp_number_integration_request).permit(
      :email, :phone_number, :preferred_time
    )
  end
end

