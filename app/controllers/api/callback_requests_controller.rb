# app/controllers/api/callback_requests_controller.rb
class Api::CallbackRequestsController < AuthenticatedController
    before_action :set_shop


    def create
      current_shop = @shop
      setting = current_shop.setting
      
      # Check rate limiting
      if setting.last_callback_request_at.present? &&
         setting.last_callback_request_at > 24.hours.ago
        
        time_remaining = 24.hours - (Time.current - setting.last_callback_request_at)
        hours_remaining = (time_remaining / 1.hour).ceil
        
        return render json: {
          error: 'rate_limited',
          message: I18n.t('callback.rate_limited', hours: hours_remaining),
          next_available_at: setting.last_callback_request_at + 24.hours,
          hours_remaining: hours_remaining
        }, status: :too_many_requests
      end
      
      callback_request = CallbackRequest.new(callback_params.merge(shop_domain: current_shop.shopify_domain))
      
      if callback_request.save
        # Update setting with last request time
        setting.update(
          last_callback_request_at: Time.current,
          callback_requests_count: setting.callback_requests_count + 1
        )
        
        # Send emails
        CallbackMailer.notify_approvers(callback_request.id).deliver_later
        CallbackMailer.send_acknowledgment(callback_request.id).deliver_later
        
        render json: {
          success: true,
          message: I18n.t('callback.success'),
          callback_request: callback_request,
          next_available_at: Time.current + 24.hours
        }
      else
        render json: {
          error: 'validation_failed',
          errors: callback_request.errors.full_messages
        }, status: :unprocessable_entity
      end
    end
    
    def check_availability
      current_shop = @shop
      setting = current_shop.setting
      
      can_request = setting.last_callback_request_at.nil? ||
                    setting.last_callback_request_at <= 24.hours.ago
      
      render json: {
        can_request: can_request,
        last_request_at: setting.last_callback_request_at,
        next_available_at: setting.last_callback_request_at ? 
                           setting.last_callback_request_at + 24.hours : nil
      }
    end
    
    private
    
    def callback_params
      params.require(:callback_request).permit(
        :name, :phone_number, :email, :preferred_time, :timezone, :notes
      )
    end
  end