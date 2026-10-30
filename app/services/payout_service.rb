# app/services/payout_service.rb - Complete fixed version

class PayoutService
  class PayoutError < StandardError; end

  def initialize(admin_user)
    @admin_user = admin_user
  end

  def create_payout(referral_partner, payout_params)
    ActiveRecord::Base.transaction do
      # Get unpaid earnings for the specified period
      unpaid_earnings = get_unpaid_earnings_for_period(
        referral_partner,
        payout_params[:earnings_from_date],
        payout_params[:earnings_to_date]
      )

      raise PayoutError, "No unpaid earnings found for the specified period" if unpaid_earnings.empty?

      total_amount = unpaid_earnings.sum(:commission_amount)
      raise PayoutError, "Total payout amount must be greater than 0" if total_amount <= 0

      # IMPROVED: Better payment info validation with detailed error messages
      payment_info = referral_partner.payment_info
      
      unless payment_info
        case referral_partner.account_type
        when 'bank'
          missing_fields = []
          missing_fields << "Bank Account Number" if referral_partner.bank_account_number.blank?
          missing_fields << "IFSC Code" if referral_partner.bank_ifsc_code.blank?
          missing_fields << "Account Name" if referral_partner.bank_account_name.blank?
          missing_fields << "Bank Name" if referral_partner.bank_name.blank?
          
          raise PayoutError, "Partner #{referral_partner.name} is missing bank details: #{missing_fields.join(', ')}"
        when 'paypal'
          raise PayoutError, "Partner #{referral_partner.name} is missing PayPal email address"
        when nil
          raise PayoutError, "Partner #{referral_partner.name} has no account type set. Please set account type to 'bank' or 'paypal'"
        else
          raise PayoutError, "Partner #{referral_partner.name} has invalid account type: #{referral_partner.account_type}"
        end
      end

      # Create payout record
      payout = referral_partner.payouts.create!(
        total_amount: total_amount,
        currency: payout_params[:currency] || 'USD',
        payment_method: payment_info[:type],
        payment_details: payment_info[:details].to_json,
        payout_date: payout_params[:payout_date] || Date.current,
        earnings_from_date: payout_params[:earnings_from_date],
        earnings_to_date: payout_params[:earnings_to_date],
        notes: payout_params[:notes],
        status: 'pending',
        created_by: @admin_user.try(:id) || @admin_user&.id || 1
      )

      # Link earnings to payout (if you have payout_earnings join table)
      unpaid_earnings.each do |earning|
        # Only create if you have PayoutEarning model, otherwise skip this
        begin
          payout.payout_earnings.create!(referral_earning: earning)
        rescue
          # Skip if PayoutEarning model doesn't exist
        end
      end

      # ✅ CRITICAL FIX: Update earnings with both payout_status AND payout_id
      update_result = unpaid_earnings.update_all(
        payout_status: 'paid',  # Use string value for enum
        payout_id: payout.id,  # Link earnings to the payout
        updated_at: Time.current
      )

      Rails.logger.info "✅ Payout created: ID=#{payout.id}, Partner=#{referral_partner.name}, Amount=$#{payout.total_amount}"
      Rails.logger.info "✅ Updated #{update_result} earnings to 'paid' status with payout_id=#{payout.id}"
      
      payout
    end
  rescue => e
    Rails.logger.error "❌ Payout creation failed: #{e.message}"
    raise PayoutError, e.message
  end

  def get_pending_payout_summary(referral_partner, to_date = Date.current)
    # Convert to_date to Date object if it's a string
    to_date = to_date.to_date if to_date.is_a?(String)
    
    # Start with the earliest unpaid earning date first
    from_date = referral_partner.referral_earnings.unpaid.minimum(:earning_date)
    
    # If no unpaid earnings, return nil
    return nil if from_date.blank?
    
    # If unpaid earnings are after our to_date, extend to_date
    if from_date > to_date
      to_date = from_date
    end
  
    unpaid_earnings = get_unpaid_earnings_for_period(referral_partner, from_date, to_date)
    
    return nil if unpaid_earnings.empty?
    
    {
      partner: referral_partner,
      earnings_count: unpaid_earnings.count,
      total_amount: unpaid_earnings.sum(:commission_amount),
      earnings_from_date: from_date,
      earnings_to_date: to_date,
      breakdown: {
        subscription: unpaid_earnings.where(transaction_type: 0).sum(:commission_amount),
        usage: unpaid_earnings.where(transaction_type: 1).sum(:commission_amount),
        onetime: unpaid_earnings.where(transaction_type: 2).sum(:commission_amount)
      },
      unpaid_earnings: unpaid_earnings
    }
  end

  def bulk_create_payouts(partner_ids, payout_params)
    results = []
    successful_count = 0
    total_amount = 0
    
    # Convert earnings_to_date to Date object if it's a string
    to_date = payout_params[:earnings_to_date]
    to_date = to_date.to_date if to_date.is_a?(String)
    to_date ||= Date.current
    
    Rails.logger.info "Starting bulk payout creation for #{partner_ids.count} partners"
    
    ReferralPartner.where(id: partner_ids).find_each do |partner|
      begin
        summary = get_pending_payout_summary(partner, to_date)
        
        if summary && summary[:total_amount] > 0
          payout = create_payout(partner, {
            earnings_from_date: summary[:earnings_from_date],
            earnings_to_date: summary[:earnings_to_date],
            payout_date: payout_params[:payout_date],
            notes: payout_params[:notes],
            currency: payout_params[:currency]
          })
          
          successful_count += 1
          total_amount += payout.total_amount
          results << { partner: partner, success: true, payout: payout, amount: payout.total_amount }
          
          Rails.logger.info "✅ Bulk payout success for #{partner.name}: $#{payout.total_amount}"
        else
          results << { partner: partner, success: false, error: "No pending earnings found" }
          Rails.logger.warn "⚠️ No pending earnings for partner #{partner.name}"
        end
      rescue PayoutError => e
        results << { partner: partner, success: false, error: e.message }
        Rails.logger.error "❌ Payout failed for #{partner.name}: #{e.message}"
      rescue => e
        results << { partner: partner, success: false, error: "Unexpected error: #{e.message}" }
        Rails.logger.error "❌ Unexpected error for #{partner.name}: #{e.message}"
      end
    end
    
    Rails.logger.info "Bulk payout completed: #{successful_count}/#{partner_ids.count} successful, total: $#{total_amount}"
    
    {
      results: results,
      summary: {
        total_partners: partner_ids.count,
        successful_count: successful_count,
        failed_count: partner_ids.count - successful_count,
        total_amount: total_amount
      }
    }
  end

  def process_payout(payout)
    return false unless payout.status == 'pending'

    begin
      payout.update!(status: 'processing')
      Rails.logger.info "Processing payout #{payout.id} for partner #{payout.referral_partner.name}"

      # Process payment based on method
      case payout.payment_method
      when 'bank_transfer', 'bank'
        result = process_bank_transfer(payout)
      when 'paypal'
        result = process_paypal_transfer(payout)
      else
        raise PayoutError, "Unsupported payment method: #{payout.payment_method}"
      end

      if result[:success]
        payout.update!(
          status: 'completed',
          transaction_reference: result[:transaction_reference],
          processed_at: Time.current
        )
        
        # ✅ IMPORTANT: Update earnings to final 'paid' status when payout completes
        payout.referral_partner.referral_earnings
              .where(payout_id: payout.id)
              .update_all(payout_status: 'paid', updated_at: Time.current)
        
        send_payout_notification(payout)
        Rails.logger.info "✅ Payout #{payout.id} completed successfully"
        true
      else
        payout.update!(status: 'failed', error_message: result[:error])
        
        # Revert earnings back to unpaid if payout fails
        payout.referral_partner.referral_earnings
              .where(payout_id: payout.id)
              .update_all(payout_status: 'unpaid', payout_id: nil, updated_at: Time.current)
        
        Rails.logger.error "❌ Payout #{payout.id} failed: #{result[:error]}"
        false
      end

    rescue => e
      payout.update!(status: 'failed', error_message: e.message)
      
      # Revert earnings back to unpaid
      payout.referral_partner.referral_earnings
            .where(payout_id: payout.id)
            .update_all(payout_status: 'unpaid', payout_id: nil, updated_at: Time.current)
      
      Rails.logger.error "❌ Payout #{payout.id} processing failed: #{e.message}"
      false
    end
  end

  def cancel_payout(payout, reason = nil)
    return false unless ['pending', 'processing'].include?(payout.status)

    begin
      payout.update!(
        status: 'cancelled',
        error_message: reason,
        cancelled_at: Time.current
      )

      # Revert all associated earnings back to unpaid
      payout.referral_partner.referral_earnings
            .where(payout_id: payout.id)
            .update_all(
              payout_status: 'unpaid',
              payout_id: nil,
              updated_at: Time.current
            )

      Rails.logger.info "✅ Payout #{payout.id} cancelled. Earnings reverted to unpaid status"
      true
    rescue => e
      Rails.logger.error "❌ Failed to cancel payout #{payout.id}: #{e.message}"
      false
    end
  end

  def retry_failed_payout(payout)
    return false unless payout.status == 'failed'
    
    # Reset status and clear error message
    payout.update!(
      status: 'pending',
      error_message: nil,
      transaction_reference: nil
    )
    
    # Attempt to process again
    process_payout(payout)
  end

  # Get summary statistics for admin dashboard
  def get_payout_statistics(date_range = nil)
    date_range ||= 30.days.ago..Date.current
    
    payouts = Payout.where(created_at: date_range)
    
    {
      total_payouts: payouts.count,
      total_amount: payouts.sum(:total_amount),
      pending_payouts: payouts.where(status: 'pending').count,
      pending_amount: payouts.where(status: 'pending').sum(:total_amount),
      completed_payouts: payouts.where(status: 'completed').count,
      completed_amount: payouts.where(status: 'completed').sum(:total_amount),
      failed_payouts: payouts.where(status: 'failed').count,
      failed_amount: payouts.where(status: 'failed').sum(:total_amount),
      average_payout: payouts.count > 0 ? payouts.sum(:total_amount) / payouts.count : 0
    }
  end

  private

  def get_unpaid_earnings_for_period(referral_partner, from_date, to_date)
    # Ensure dates are Date objects
    from_date = from_date.to_date if from_date.is_a?(String)
    to_date = to_date.to_date if to_date.is_a?(String)
    
    earnings = referral_partner.referral_earnings.unpaid.includes(:referral_shop)
    
    # Apply date filters if provided
    if from_date.present? && to_date.present?
      earnings = earnings.where(earning_date: from_date..to_date)
    elsif from_date.present?
      earnings = earnings.where('earning_date >= ?', from_date)
    elsif to_date.present?
      earnings = earnings.where('earning_date <= ?', to_date)
    end
    
    earnings
  end

  def process_bank_transfer(payout)
    # Simulate bank transfer processing
    # Replace with actual bank API integration
    
    sleep(1) # Simulate processing time
    
    # For demo purposes, assume all bank transfers succeed
    {
      success: true,
      transaction_reference: "BANK_#{Time.current.to_i}_#{payout.id}",
      message: "Bank transfer initiated successfully"
    }
  rescue => e
    {
      success: false,
      error: "Bank transfer failed: #{e.message}"
    }
  end

  def process_paypal_transfer(payout)
    # Simulate PayPal transfer processing
    # Replace with actual PayPal API integration
    
    sleep(1) # Simulate processing time
    
    # For demo purposes, assume all PayPal transfers succeed
    {
      success: true,
      transaction_reference: "PP_#{Time.current.to_i}_#{payout.id}",
      message: "PayPal transfer completed successfully"
    }
  rescue => e
    {
      success: false,
      error: "PayPal transfer failed: #{e.message}"
    }
  end

  def send_payout_notification(payout)
    partner = payout.referral_partner
    Rails.logger.info "Sending payout notifications for payout #{payout.id} (partner: #{partner.name})"

    # Email to partner
    begin
      PayoutMailer.payout_completed_to_partner(payout).deliver_now
      Rails.logger.info "✅ Payout email sent to partner: #{partner.email}"
    rescue => e
      Rails.logger.error "❌ Failed to send payout email to partner: #{e.message}"
    end

    # Email to admin(s) - ENV['WHATSAPP_APPROVERS_EMAIL_LIST'] (comma-separated)
    if ENV['WHATSAPP_APPROVERS_EMAIL_LIST'].to_s.strip.present?
      begin
        PayoutMailer.payout_completed_to_admin(payout).deliver_now
        Rails.logger.info "✅ Payout notification sent to admin(s)"
      rescue => e
        Rails.logger.error "❌ Failed to send payout email to admin: #{e.message}"
      end
    end
  end
end