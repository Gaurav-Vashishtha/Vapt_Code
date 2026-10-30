class ReferralAdmin::ReferralPartnersController < ReferralAdmin::ApplicationController
  # before_action :require_admin_login
  before_action :set_partner, only: [:show, :edit, :update, :destroy, :toggle_active, :verify_account, :create_payout, :fetch_real_earnings_last_30_days, :update_notes]
  
  def index
    @min_total_shops = params[:min_total_shops].to_s.strip
    @pending_account_only = params[:pending_account].to_s == "1"
    @pending_shop_approvals_only = params[:pending_shop_approvals].to_s == "1"
    @total_partners_count = ReferralPartner.count
    @active_partners_count = ReferralPartner.where(active: true).count

    partners = ReferralPartner
                 .left_joins(:referral_shops)
                 .select(
                   "referral_partners.*",
                   "COUNT(referral_shops.id) AS total_shops_count",
                   "SUM(CASE WHEN referral_shops.approved = TRUE THEN 1 ELSE 0 END) AS approved_shops_count",
                   "SUM(CASE WHEN referral_shops.approved = FALSE THEN 1 ELSE 0 END) AS pending_shops_count"
                 )
                 .group("referral_partners.id")

    if @min_total_shops.present?
      min = @min_total_shops.to_i
      partners = partners.having("COUNT(referral_shops.id) >= ?", min)
    end

    if @pending_account_only
      partners = partners.where.not(account_type: [nil, ""]).where(account_verified: [false, nil])
    end

    if @pending_shop_approvals_only
      partners = partners.having("SUM(CASE WHEN referral_shops.approved = FALSE THEN 1 ELSE 0 END) > 0")
    end

    @partners = partners.order(Arel.sql("referral_partners.created_at DESC, referral_partners.name ASC"))
    @pending_shops_count = ReferralShop.pending_approval.count
  end
  
  def show
    @total_shops = @partner.referral_shops.count
    @approved_shops = @partner.referral_shops.approved.count
    @pending_shops = @partner.referral_shops.pending_approval.count
    @total_commission = @partner.total_commission_earned(:all_time)
    @commission_30_days = @partner.total_commission_earned(:last_30_days)
    @shops = @partner.referral_shops.order(created_at: :desc)
    @payouts = @partner.payouts.order(payout_date: :desc).limit(50)
    @total_unpaid = @partner.total_unpaid_earnings
    payout_service = PayoutService.new(current_referral_admin)
    @pending_payout_summary = payout_service.get_pending_payout_summary(@partner, Date.current)
  end
  
  def new
    @partner = ReferralPartner.new
  end
  
  def create
    @partner = ReferralPartner.new(partner_params)
    
    # Store the plain password before it gets encrypted
    plain_password = params.dig(:referral_partner, :password)
    
    if @partner.save
      # 🎉 SEND WELCOME EMAIL TO PARTNER WITH PASSWORD
      begin
        WelcomeMailer.referral_partner_signup(@partner.id, plain_password).deliver_now
        Rails.logger.info "✅ Welcome email sent to partner: #{@partner.email}"
      rescue => e
        Rails.logger.error "❌ Failed to send welcome email to #{@partner.email}: #{e.message}"
      end

      # 📧 SEND ADMIN NOTIFICATION EMAIL
      begin
        WelcomeMailer.referral_partner_created_admin_notification(@partner.id).deliver_now
        Rails.logger.info "✅ Admin notification sent for new partner: #{@partner.name}"
      rescue => e
        Rails.logger.error "❌ Failed to send admin notification: #{e.message}"
      end

      # ✅ FIXED: Use correct route helper for ReferralAdmin namespace
      redirect_to referral_admin_referral_partner_path(@partner), 
                  notice: 'Partner created successfully and welcome email sent with login credentials.'
    else
      render :new
    end
  end
  
  def edit
  end
  
  def update
    if @partner.update(partner_params)
      redirect_to referral_admin_referral_partner_path(@partner), notice: 'Partner updated successfully.'
    else
      render :edit
    end
  end
  
  def destroy
    @partner.destroy
    redirect_to referral_admin_referral_partners_path, notice: 'Partner deleted successfully.'
  end
  
  def toggle_active
    @partner.update!(active: !@partner.active)
    redirect_to referral_admin_referral_partners_path, 
                notice: "Partner #{@partner.active? ? 'activated' : 'deactivated'} successfully."
  end
  
  def verify_account
    @partner.update!(
      account_verified: true,
      account_verified_at: Time.current
    )
    redirect_to referral_admin_referral_partner_path(@partner), notice: 'Account verified successfully!'
  end

  # Admin-only free-text notes on the partner detail page. Saved without running
  # the full model validations so legacy bank/IFSC data can't block a note edit.
  def update_notes
    notes = params.dig(:referral_partner, :notes).to_s.strip.presence
    @partner.update_columns(notes: notes, updated_at: Time.current)

    respond_to do |format|
      format.json { render json: { success: true, notes: @partner.notes, updated_at: @partner.updated_at.strftime("%b %d, %Y %I:%M %p") } }
      format.html { redirect_to referral_admin_partner_path(@partner), notice: 'Notes saved.' }
    end
  rescue StandardError => e
    respond_to do |format|
      format.json { render json: { success: false, error: e.message }, status: :unprocessable_entity }
      format.html { redirect_to referral_admin_partner_path(@partner), alert: "Could not save notes: #{e.message}" }
    end
  end

  def create_payout
    payout_service = PayoutService.new(current_referral_admin)
    summary = payout_service.get_pending_payout_summary(@partner, Date.current)

    if summary.blank?
      redirect_to referral_admin_partner_path(@partner), alert: 'No unpaid earnings to payout.'
      return
    end

    payout = payout_service.create_payout(@partner, {
      earnings_from_date: summary[:earnings_from_date],
      earnings_to_date: summary[:earnings_to_date],
      payout_date: Date.current,
      notes: params.dig(:payout, :notes)
    })

    redirect_to referral_admin_payout_path(payout),
                notice: "Payout created: $#{format('%.2f', payout.total_amount)} (pending)."
  rescue PayoutService::PayoutError => e
    redirect_to referral_admin_partner_path(@partner), alert: "Could not create payout: #{e.message}"
  end
  
  # Fetches "real" earnings from Shopify Partner API for this partner's approved shops
  # over the last 30 days and caches the result for display on the index.
  def fetch_real_earnings_last_30_days
    token = ENV["SHOPIFY_PARTNER_ACCESS_TOKEN"].to_s.strip
    org_id = ENV["SHOPIFY_ORGANIZATION_ID"].to_s.strip

    if token.blank? || org_id.blank?
      msg = "Missing SHOPIFY_PARTNER_ACCESS_TOKEN or SHOPIFY_ORGANIZATION_ID env var."
      respond_to do |format|
        format.json { render json: { success: false, error: msg }, status: :unprocessable_entity }
        format.html { redirect_to referral_admin_referral_partners_path, alert: msg }
      end
      return
    end

    domains = @partner.referral_shops.approved.pluck(:shop_domain)
    if domains.empty?
      msg = "No approved shops for #{@partner.name}."
      respond_to do |format|
        format.json { render json: { success: false, error: msg }, status: :unprocessable_entity }
        format.html { redirect_to referral_admin_referral_partners_path, alert: msg }
      end
      return
    end

    fetcher = NetworkServices::ShopifyPartnerRevenueFetcher.new(token, org_id)
    results = fetcher.get_multiple_shops_earnings(domains)
    Rails.cache.write("referral_partner:#{@partner.id}:real_earnings_last_30_days", results, expires_in: 15.minutes)

    total = results[:total_earnings_all_partners].to_f
    respond_to do |format|
      format.json do
        render json: {
          success: true,
          partner_id: @partner.id,
          partner_name: @partner.name,
          total_earnings_last_30_days: total,
          cached_for_seconds: 15.minutes.to_i,
          fetched_at: Time.current.iso8601
        }
      end
      format.html do
        redirect_to referral_admin_referral_partners_path,
                    notice: "Fetched last 30 days earnings for #{@partner.name}: $#{format('%.2f', total)}"
      end
    end
  rescue StandardError => e
    respond_to do |format|
      format.json { render json: { success: false, error: e.message }, status: :unprocessable_entity }
      format.html { redirect_to referral_admin_referral_partners_path, alert: "Could not fetch earnings: #{e.message}" }
    end
  end

  private
  
  def set_partner
    @partner = ReferralPartner.find(params[:id])
  end
  
  def partner_params
    params.require(:referral_partner).permit(
      :name, :email, :phone, :password, :password_confirmation,
      :subscription_commission_rate, :usage_commission_rate, :onetime_commission_rate,
      :active, :notes, :account_type, :bank_account_number, :bank_ifsc_code,
      :bank_account_name, :bank_name, :paypal_email, :account_verified
    )
  end
end