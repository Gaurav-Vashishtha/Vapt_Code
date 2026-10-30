# app/services/referral_revenue_sync_service.rb
class ReferralRevenueSyncService
  def initialize(organization_id, partner_access_token)
    @fetcher = NetworkServices::ShopifyPartnerRevenueFetcher.new(partner_access_token, organization_id)
  end
  
  def sync_partner_earnings(referral_partner, approved_only: true, include_historical: false)
    results = []
    shops = approved_only ? referral_partner.referral_shops.approved_and_active : referral_partner.referral_shops.active
    
    shops.each do |shop|
      result = if include_historical && !shop.historical_sync_completed
        sync_shop_historical_earnings(shop)
      else
        sync_shop_earnings(shop)
      end
      results << result
    end
    
    results
  end

  def sync_shop_earnings(referral_shop, from_date: nil, to_date: nil)
    begin
      # Default to last 30 days if no date range specified
      from_date = referral_shop.last_sync_date || Date.current - 30.days
      to_date = Date.current
      Rails.logger.info "Syncing earnings for shop #{referral_shop.shop_domain} from #{from_date} to #{to_date}"
      
      # Get earnings from Shopify for specified period
      result = @fetcher.get_earnings_for_period(
        referral_shop.shop_domain, 
        from_date, 
        to_date
      )
      
      return { shop: referral_shop, success: false, error: result[:error] } unless result[:success]
      
      earnings_data = result[:data]
      partner = referral_shop.referral_partner
      
      Rails.logger.info "Earnings data for #{referral_shop.shop_domain}: #{earnings_data.inspect}"
      
      # Process each transaction type
      commission_data = []
      
      # Process subscription revenue
      if earnings_data[:breakdown][:subscription_revenue] > 0
        commission = calculate_and_save_earning(
          referral_shop, 
          :subscription,  # CHANGED: Use symbol instead of string
          earnings_data[:breakdown][:subscription_revenue],
          partner.subscription_commission_rate,
          from_date,
          to_date
        )
        commission_data << commission if commission
      end
      
      # Process usage revenue  
      if earnings_data[:breakdown][:usage_revenue] > 0
        commission = calculate_and_save_earning(
          referral_shop,
          :usage,  # CHANGED: Use symbol instead of string
          earnings_data[:breakdown][:usage_revenue],
          partner.usage_commission_rate,
          from_date,
          to_date
        )
        commission_data << commission if commission
      end
      
      # Process one-time revenue
      if earnings_data[:breakdown][:one_time_revenue] > 0
        commission = calculate_and_save_earning(
          referral_shop,
          :onetime,  # CHANGED: Use symbol instead of string
          earnings_data[:breakdown][:one_time_revenue], 
          partner.onetime_commission_rate,
          from_date,
          to_date
        )
        commission_data << commission if commission
      end
      
      # Update shop's tracking
      update_shop_sync_tracking(referral_shop, earnings_data, to_date)
      
      Rails.logger.info "Created/updated #{commission_data.count} earnings for #{referral_shop.shop_domain}"
      
      { 
        shop: referral_shop, 
        success: true, 
        earnings_data: earnings_data,
        commission_data: commission_data,
        total_commission: commission_data.sum { |c| c[:commission_amount] },
        sync_period: { from: from_date, to: to_date }
      }
      
    rescue => e
      Rails.logger.error "Error syncing shop #{referral_shop.shop_domain}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      { shop: referral_shop, success: false, error: e.message }
    end
  end

  def sync_shop_historical_earnings(referral_shop)
    begin
      date_range = referral_shop.historical_sync_date_range
      return { shop: referral_shop, success: false, error: "No historical date range available" } unless date_range
      
      from_date = date_range[:from]
      to_date = date_range[:to]
      
      Rails.logger.info "Syncing historical earnings for shop #{referral_shop.shop_domain} from #{from_date} to #{to_date}"
      
      # Sync historical data
      result = sync_shop_earnings(referral_shop, from_date: from_date, to_date: to_date)
      
      # Mark historical sync as completed if successful
      if result[:success]
        referral_shop.mark_historical_sync_completed!
        result[:historical_sync] = true
      end
      
      result
    rescue => e
      Rails.logger.error "Error syncing historical data for #{referral_shop.shop_domain}: #{e.message}"
      { shop: referral_shop, success: false, error: e.message, historical_sync: false }
    end
  end
  
  def sync_all_partners(include_historical: false)
    ReferralPartner.active.includes(:referral_shops).map do |partner|
      {
        partner: partner,
        results: sync_partner_earnings(partner, approved_only: true, include_historical: include_historical)
      }
    end
  end
  
  # Sync only shops that need historical sync
  def sync_pending_historical
    shops_needing_sync = ReferralShop.approved_and_active.needs_historical_sync
    
    shops_needing_sync.map do |shop|
      sync_shop_historical_earnings(shop)
    end
  end
  
  private
  
  def calculate_and_save_earning(referral_shop, transaction_type, revenue_amount, commission_rate, from_date, to_date)
    return nil if revenue_amount <= 0 || commission_rate <= 0
    
    commission_amount = (revenue_amount * commission_rate / 100).round(2)
    
    Rails.logger.info "Calculating earning for #{referral_shop.shop_domain}: #{transaction_type}, revenue: #{revenue_amount}, rate: #{commission_rate}%, commission: #{commission_amount}"
    
    # Use the middle date of the period as earning_date, or end date if it's a single day
    earning_date = from_date == to_date ? to_date : from_date + ((to_date - from_date) / 2).days
    
    # Check if we already have an earning for this exact period
    existing_earning = ReferralEarning.find_by(
      referral_shop: referral_shop,
      transaction_type: transaction_type,
      earning_date: from_date..to_date
    )
    
    if existing_earning
      Rails.logger.info "Updating existing earning ID: #{existing_earning.id}"
      # Update existing earning
      existing_earning.update!(
        revenue_amount: revenue_amount,
        commission_rate: commission_rate,
        commission_amount: commission_amount,
        processed_at: Time.current,
        payout_status: :unpaid  # ADDED: Ensure payout_status is set
      )
      earning = existing_earning
    else
      Rails.logger.info "Creating new earning for #{referral_shop.shop_domain}"
      # Create new earning
      earning = ReferralEarning.create!(
        referral_partner: referral_shop.referral_partner,
        referral_shop: referral_shop,
        transaction_type: transaction_type,  # This will now be a symbol (:subscription, :usage, :onetime)
        revenue_amount: revenue_amount,
        commission_rate: commission_rate,
        commission_amount: commission_amount,
        earning_date: earning_date,
        currency: 'USD',
        payout_status: :unpaid  # This will now be a symbol (:unpaid)
      )
      Rails.logger.info "Created earning ID: #{earning.id} with transaction_type: #{earning.transaction_type}, payout_status: #{earning.payout_status}"
    end
    
    {
      transaction_type: transaction_type,
      revenue_amount: revenue_amount,
      commission_rate: commission_rate,
      commission_amount: commission_amount,
      earning: earning,
      period: { from: from_date, to: to_date }
    }
  end
  
  def update_shop_sync_tracking(referral_shop, earnings_data, sync_date)
    total_revenue = earnings_data[:total_earnings]
    
    referral_shop.update!(
      total_lifetime_revenue: total_revenue,
      first_revenue_at: referral_shop.first_revenue_at || Time.current,
      last_sync_date: sync_date
    )
  end
end