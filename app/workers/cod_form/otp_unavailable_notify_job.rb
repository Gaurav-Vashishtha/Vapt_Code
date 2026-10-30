# frozen_string_literal: true

module CodForm
  # CodForm::OtpUnavailableNotifyJob.perform_async(shop_id)   (K.9, ARCHITECTURE.md I.6, decision 15)
  #
  # Enqueued by OtpService each time an OTP could not be sent and the order went on unverified.
  # The merchant gets at most one email per 24 hours (CodForm::Cache.store key
  # codf:otp_unavail_mail:<shop_id>, claimed atomically).
  class OtpUnavailableNotifyJob < ApplicationJob
    sidekiq_options queue: "default", retry: 2

    WINDOW = 24.hours

    def self.cache_key(shop_id)
      "codf:otp_unavail_mail:#{shop_id}"
    end

    def perform(shop_id)
      shop = Shop.find_by(id: shop_id)
      return if shop.nil? || shop.owner_email.blank?

      key = self.class.cache_key(shop.id)
      return unless CodForm::Cache.store.write(key, Time.current.utc.iso8601, unless_exist: true, expires_in: WINDOW)

      begin
        CodFormMailer.otp_unavailable_notice(shop.id).deliver_now
      rescue StandardError
        CodForm::Cache.store.delete(key) # let the retry (or the next bypass) send it
        raise
      end
    end
  end
end
