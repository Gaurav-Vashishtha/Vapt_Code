# app/controllers/whatsapp_admin/whatsapp_approvals_controller.rb
# THIS IS THE ONLY CONTROLLER FILE YOU NEED

class WhatsappAdmin::WhatsappApprovalsController < ApplicationController
    require 'net/http'
    require 'json'
    
    before_action :authenticate_admin!
    before_action :set_shop_domain, only: [:approve, :reject]
    
    CLIENT_TOKEN = "6e2943c2-496e-40d6-848f-fd04f4af197c"
    BASE_URL = "https://app.codking.tech"
    
    def index
      @pending_shops = fetch_pending_approvals
      @message = flash[:notice] || flash[:alert]
    end
    
    def approve
      begin
        result = review_whatsapp_approval(@shop_domain, "approved")
        
        if result[:success]
          flash[:notice] = "✅ WhatsApp approved for #{@shop_domain}"
          Rails.logger.info "WhatsApp approved for #{@shop_domain}"
        else
          flash[:alert] = "❌ Failed to approve: #{result[:error]}"
          Rails.logger.error "Failed to approve WhatsApp for #{@shop_domain}: #{result[:error]}"
        end
      rescue => e
        flash[:alert] = "❌ Error: #{e.message}"
        Rails.logger.error "Error approving WhatsApp for #{@shop_domain}: #{e.message}"
      end
      
      redirect_to whatsapp_admin_whatsapp_approvals_path
    end
    
    def reject
      begin
        result = review_whatsapp_approval(@shop_domain, "rejected")
        
        if result[:success]
          flash[:notice] = "❌ WhatsApp rejected for #{@shop_domain}"
          Rails.logger.info "WhatsApp rejected for #{@shop_domain}"
        else
          flash[:alert] = "❌ Failed to reject: #{result[:error]}"
          Rails.logger.error "Failed to reject WhatsApp for #{@shop_domain}: #{result[:error]}"
        end
      rescue => e
        flash[:alert] = "❌ Error: #{e.message}"
        Rails.logger.error "Error rejecting WhatsApp for #{@shop_domain}: #{e.message}"
      end
      
      redirect_to whatsapp_admin_whatsapp_approvals_path
    end
    
    def refresh
      flash[:notice] = "🔄 Dashboard refreshed"
      redirect_to whatsapp_admin_whatsapp_approvals_path
    end
    
    private
    
    def authenticate_admin!
      authenticate_or_request_with_http_basic("Cod King Admin") do |username, password|
        # CHANGE THESE CREDENTIALS BEFORE DEPLOYING TO PRODUCTION
        username == "admin" && password == "password123"
      end
    end
    
    def set_shop_domain
      @shop_domain = params[:shop_domain]
      
      if @shop_domain.blank?
        flash[:alert] = "❌ Shop domain is required"
        redirect_to whatsapp_admin_whatsapp_approvals_path and return
      end
    end
    
    def fetch_pending_approvals
      begin
        uri = URI("#{BASE_URL}/order_confirmations/pending_whatsapp")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 30
        
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request.body = {
          clientToken: CLIENT_TOKEN
        }.to_json
        
        response = http.request(request)
        
        if response.code == '200'
          data = JSON.parse(response.body)
          return data['approvalStatus'] || []
        else
          Rails.logger.error "Failed to fetch pending approvals: #{response.code} - #{response.body}"
          return []
        end
      rescue => e
        Rails.logger.error "Error fetching pending approvals: #{e.message}"
        return []
      end
    end
    
    def review_whatsapp_approval(shop_domain, approval_status)
      begin
        uri = URI("#{BASE_URL}/order_confirmations/review_whatsapp")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 30
        
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request.body = {
          clientToken: CLIENT_TOKEN,
          shopifyDomain: shop_domain,
          approvalStatus: approval_status
        }.to_json
        
        response = http.request(request)
        
        if response.code == '200'
          { success: true, data: JSON.parse(response.body) }
        else
          { success: false, error: "HTTP #{response.code}: #{response.body}" }
        end
      rescue => e
        { success: false, error: e.message }
      end
    end
  end