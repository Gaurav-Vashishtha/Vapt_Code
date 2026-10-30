module AdminJobs
  class PreOrderOtpAbandonmentJob < ApplicationJob
    sidekiq_options queue: 'administration'

    def perform
      puts 'PreOrder OTP Abandonment job started'

      # DB-level filter for IN_PROGRESS, stale time, and non-empty cart_details
      stale_otps = PreOrderOtp
        .where(order_status: 'IN_PROGRESS')
        .where('updated_at < ?', 30.minutes.ago)
        .where('created_at > ?', 6.hours.ago)
        .where("array_length(cart_details, 1) > 0")

      puts "Found #{stale_otps.count} eligible records"

      abandoned_sessions = Set.new

      stale_otps.find_each do |otp_record|
        begin
          otp_record.update(order_status: 'AbandonedCheckout')
          abandoned_sessions << [otp_record.shop_id, otp_record.device_id] if otp_record.device_id.present?
          puts "✅ Updated OTP ##{otp_record.id} to Abandoned_Checkout"
        rescue => e
          puts "❌ Error updating OTP ##{otp_record.id}: #{e.message} #{e.backtrace}"
        end
      end

      enqueue_draft_orders(abandoned_sessions)

      puts 'PreOrder OTP Abandonment job completed'
    end

    private

    # One draft-order sync per cart session (several OTP rows share a device_id),
    # only for shops with additional_settings.pre_order_otp_draft_orders on.
    def enqueue_draft_orders(sessions)
      return if sessions.empty?

      enabled = AdditionalSetting.where(shop_id: sessions.map(&:first).uniq, pre_order_otp_draft_orders: true)
                                 .pluck(:shop_id).to_set
      sessions.each do |shop_id, device_id|
        PreOrderOtpDraftJobs::SyncJob.perform_async(shop_id, device_id.to_s) if enabled.include?(shop_id)
      end
    rescue => e
      puts "❌ Draft order enqueue failed: #{e.message}"
    end

  end
end