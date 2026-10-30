class ReferralAdmin::PayoutsController < ReferralAdmin::ApplicationController
  before_action :set_payout, only: [:show, :process_payout, :cancel, :download_receipt]

  def index
    @payouts = Payout.includes(:referral_partner)
                    .order(created_at: :desc)
                    .limit(50)
    
    @payouts = apply_filters(@payouts)
    
    @summary = {
      total_pending: Payout.where(status: 'pending').sum(:total_amount),
      total_completed: Payout.where(status: 'completed').sum(:total_amount),
      total_this_month: Payout.where(
        payout_date: Date.current.beginning_of_month..Date.current.end_of_month
      ).sum(:total_amount),
      pending_count: Payout.where(status: 'pending').count,
      completed_count: Payout.where(status: 'completed').count,
      processing_count: Payout.where(status: 'processing').count
    }
  end

  def show
    @earnings = @payout.referral_earnings
                      .includes(:referral_shop)
                      .order(:earning_date)
    
    # FIXED: Calculate earnings breakdown without grouping issues
    # Use the already loaded @earnings instead of creating a new grouped query
    @earnings_breakdown = {}
    @earnings.each do |earning|
      type = earning.transaction_type || 'unknown'
      @earnings_breakdown[type] ||= 0
      @earnings_breakdown[type] += earning.commission_amount
    end
    
    # Calculate earnings breakdown by shop
    @shops_breakdown = {}
    @earnings.each do |earning|
      shop_domain = earning.referral_shop&.shop_domain || 'Unknown Shop'
      @shops_breakdown[shop_domain] ||= 0
      @shops_breakdown[shop_domain] += earning.commission_amount
    end
  end

  def new
    @partners_with_pending = ReferralPartner.active
                                          .joins(:referral_earnings)
                                          .where(referral_earnings: { payout_status: 0 })  # 0 = unpaid
                                          .distinct
                                          .order(:name)
    
    # Debug info
    Rails.logger.info "Partners with pending: #{@partners_with_pending.count}"
    @partners_with_pending.each do |partner|
      unpaid_amount = partner.referral_earnings.where(payout_status: 0).sum(:commission_amount)
      Rails.logger.info "  #{partner.name}: $#{unpaid_amount}"
    end
  end

  def pending_summary
    @pending_payouts = Payout.where(status: 'pending')
                             .includes(:referral_partner)
                             .order(created_at: :desc)

    @pending_by_partner = @pending_payouts.group_by(&:referral_partner)

    @totals = {
      total_amount: @pending_payouts.sum(&:total_amount),
      payout_count: @pending_payouts.size,
      partner_count: @pending_by_partner.size
    }

    @unpaid_by_partner = ReferralEarning.unpaid
                                        .joins(:referral_partner)
                                        .group('referral_partners.name', 'referral_partners.id')
                                        .sum(:commission_amount)
    @unpaid_total = ReferralEarning.unpaid.sum(:commission_amount)

    respond_to do |format|
      format.html
      format.json do
        render json: {
          totals: @totals,
          pending_payouts: @pending_payouts.map do |p|
            {
              id: p.id,
              partner: p.referral_partner&.name,
              amount: p.total_amount,
              payout_date: p.payout_date,
              created_at: p.created_at
            }
          end,
          unpaid_earnings: {
            total: @unpaid_total,
            by_partner: @unpaid_by_partner
          }
        }
      end
    end
  end

  def partner_summary
    partner = ReferralPartner.find(params[:partner_id])
    payout_service = PayoutService.new(current_referral_admin)
    @summary = payout_service.get_pending_payout_summary(partner, params[:to_date]&.to_date)
    
    if @summary.nil?
      render json: { error: "No pending earnings found for this partner" }, status: 404
      return
    end

    render json: @summary
  end

  def create_partner_payout
    partner = ReferralPartner.find(params[:referral_partner_id])
    
    # Debug the admin user
    admin_user = current_referral_admin
    Rails.logger.info "Creating payout with admin: #{admin_user.inspect}"
    
    payout_service = PayoutService.new(admin_user)
    
    begin
      @payout = payout_service.create_payout(partner, payout_params)
      
      Rails.logger.info "✅ Payout created: ID=#{@payout.id}, Status=#{@payout.status}, Amount=#{@payout.total_amount}"
      
      redirect_to referral_admin_payout_path(@payout), 
                  notice: "Payout created successfully for #{partner.name} - $#{@payout.total_amount}"
    rescue PayoutService::PayoutError => e
      Rails.logger.error "❌ PayoutService error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      redirect_to new_referral_admin_payout_path, alert: "Failed to create payout: #{e.message}"
    rescue => e
      Rails.logger.error "❌ Unexpected error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      redirect_to new_referral_admin_payout_path, alert: "Unexpected error: #{e.message}"
    end
  end

  def bulk_create
    partner_ids = params[:partner_ids]&.reject(&:blank?)
    
    if partner_ids.blank?
      redirect_to new_referral_admin_payout_path, alert: "Please select at least one partner"
      return
    end

    Rails.logger.info "Bulk creating payouts for partners: #{partner_ids}"
    
    payout_service = PayoutService.new(current_referral_admin)
    
    # ✅ FIXED: The service now returns a hash with :results and :summary keys
    bulk_result = payout_service.bulk_create_payouts(partner_ids, bulk_payout_params)
    results = bulk_result[:results]
    summary = bulk_result[:summary]
    
    # Use the summary data from the service
    successful_count = summary[:successful_count]
    total_amount = summary[:total_amount]
    
    Rails.logger.info "Bulk create results: #{successful_count}/#{summary[:total_partners]} successful, total: $#{total_amount}"
    
    if successful_count > 0
      flash[:notice] = "Successfully created #{successful_count} payouts totaling $#{total_amount}"
    end
    
    if summary[:failed_count] > 0
      failed_partners = results.reject { |r| r[:success] }.map { |r| "#{r[:partner].name}: #{r[:error]}" }
      flash[:alert] = "Some payouts failed: #{failed_partners.join('; ')}"
    end
    
    redirect_to referral_admin_payouts_path
  end

  def process_payout
    payout_service = PayoutService.new(current_referral_admin)
    
    if payout_service.process_payout(@payout)
      redirect_to referral_admin_payout_path(@payout), 
                  notice: "Payout processed successfully"
    else
      redirect_to referral_admin_payout_path(@payout), 
                  alert: "Failed to process payout: #{@payout.error_message}"
    end
  end

  def cancel
    payout_service = PayoutService.new(current_referral_admin)
    
    if payout_service.cancel_payout(@payout, params[:cancellation_reason])
      redirect_to referral_admin_payout_path(@payout), 
                  notice: "Payout cancelled successfully"
    else
      redirect_to referral_admin_payout_path(@payout), 
                  alert: "Cannot cancel payout in #{@payout.status} status"
    end
  end

  private

  def current_referral_admin
    # FIXED: Return a proper admin object
    # Replace this with your actual admin authentication method
    @current_referral_admin ||= begin
      if session[:admin_user_id]
        # If you have an AdminUser model:
        # AdminUser.find(session[:admin_user_id])
        
        # For now, create a mock admin object:
        OpenStruct.new(
          id: session[:admin_user_id] || 1,
          name: "Admin User",
          email: "admin@example.com"
        )
      else
        # Create default admin for testing
        OpenStruct.new(id: 1, name: "System Admin", email: "admin@system.com")
      end
    end
  end

  def set_payout
    @payout = Payout.find(params[:id])
  end

  def apply_filters(payouts)
    payouts = payouts.where(status: params[:status]) if params[:status].present?
    payouts = payouts.where(referral_partner_id: params[:partner_id]) if params[:partner_id].present?
    
    if params[:from_date].present? && params[:to_date].present?
      payouts = payouts.where(payout_date: params[:from_date]..params[:to_date])
    end
    
    payouts
  end

  def payout_params
    params.require(:payout).permit(
      :earnings_from_date, :earnings_to_date, :payout_date, :notes
    )
  end

  def bulk_payout_params
    params.permit(:earnings_from_date, :earnings_to_date, :payout_date, :notes)
  end
end