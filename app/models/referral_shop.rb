class ReferralShop < ApplicationRecord
    belongs_to :referral_partner
    has_many :referral_earnings, dependent: :destroy
    
    validates :shop_domain, presence: true, uniqueness: { scope: :referral_partner_id }
    validates :shop_domain, format: { 
      with: /\A[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9]\z/, 
      message: "must be a valid shop domain" 
    }
    
    scope :active, -> { where(active: true) }
    scope :approved, -> { where(approved: true) }
    scope :pending_approval, -> { where(approved: false) }
    scope :approved_and_active, -> { active.approved }
    scope :needs_historical_sync, -> { where(historical_sync_completed: false) }

    
    before_validation :normalize_shop_domain
    

    def mark_historical_sync_completed!
        update!(
          historical_sync_completed: true,
          last_sync_date: Date.current
        )
      end
    
      def historical_sync_date_range
        return nil unless created_at
        
        # Start from 30 days before creation, or custom date if specified
        from_date = historical_sync_from_date || (created_at.to_date - 30.days)
        to_date = created_at.to_date
        
        # Ensure we have a valid range
        return nil if from_date >= to_date
        
        { from: from_date, to: to_date }
      end
    
      def next_sync_from_date
        if last_sync_date
          # If we have a last sync date, start from the day after that
          last_sync_date + 1.day
        else
          # If no last sync date (first time sync), sync from 30 days ago
          Date.current - 30.days
        end
      end

    def normalized_domain
      shop_domain.gsub(/\.myshopify\.com$/, '')
    end
    
    def full_domain
      domain = normalized_domain
      domain.include?('.myshopify.com') ? domain : "#{domain}.myshopify.com"
    end
    
    def total_revenue(period = :all_time)
      return 0 unless approved? # Only calculate for approved shops
      
      earnings = case period
      when :last_30_days
        referral_earnings.where(earning_date: 30.days.ago.to_date..Date.current)
      when :current_month
        referral_earnings.where(earning_date: Date.current.beginning_of_month..Date.current.end_of_month)
      else
        referral_earnings
      end
      
      earnings.sum(:revenue_amount)
    end
    
    def total_commission(period = :all_time)
      return 0 unless approved? # Only calculate for approved shops
      
      earnings = case period
      when :last_30_days
        referral_earnings.where(earning_date: 30.days.ago.to_date..Date.current)
      when :current_month
        referral_earnings.where(earning_date: Date.current.beginning_of_month..Date.current.end_of_month)
      else
        referral_earnings
      end
      
      earnings.sum(:commission_amount)
    end
    
    def revenue_breakdown(period = :all_time)
      return {} unless approved? # Only calculate for approved shops
      
      earnings = case period
      when :last_30_days
        referral_earnings.where(earning_date: 30.days.ago.to_date..Date.current)
      when :current_month
        referral_earnings.where(earning_date: Date.current.beginning_of_month..Date.current.end_of_month)
      else
        referral_earnings
      end
      
      earnings.group(:transaction_type).sum(:revenue_amount)
    end
    
    def approve!(approved_by_name)
      update!(
        approved: true,
        approved_at: Time.current,
        approved_by: approved_by_name,
        rejection_reason: nil
      )
    end
    
    def reject!(reason, rejected_by_name)
      update!(
        approved: false,
        approved_at: nil,
        approved_by: rejected_by_name,
        rejection_reason: reason
      )
    end
    
    def approval_status
      if approved?
        "Approved"
      elsif rejection_reason.present?
        "Rejected"
      else
        "Pending"
      end
    end
    
    private
    
    def normalize_shop_domain
      if shop_domain.present?
        # Remove .myshopify.com if present
        self.shop_domain = shop_domain.gsub(/\.myshopify\.com$/i, '')
        # Convert to lowercase
        self.shop_domain = shop_domain.downcase
      end
    end
  end