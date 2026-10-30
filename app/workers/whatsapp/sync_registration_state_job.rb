module Whatsapp
  # Refreshes each connected number's Cloud API registration state from Meta.
  #
  # Run this once after deploying the registration gate: it stamps registered_at
  # on numbers that are already registered, so the gate never turns off a number
  # that was working. Safe to run repeatedly / on a schedule.
  #
  #   Whatsapp::SyncRegistrationStateJob.new.perform            # every shop
  #   Whatsapp::SyncRegistrationStateJob.new.perform(shop_id)   # one shop
  class SyncRegistrationStateJob < ApplicationJob
    sidekiq_options queue: 'administration', retry: 1

    def perform(shop_id = nil)
      scope = WhatsappAccount.active.where.not(phone_number_id: [nil, ''])
      scope = scope.where(shop_id: shop_id) if shop_id.present?

      checked = 0
      unregistered = []

      scope.find_each do |account|
        Meta::PhoneNumberService.call(account: account, operation: :status)
        checked += 1
        unregistered << account.id unless account.reload.registered?
      rescue StandardError => e
        Rails.logger.warn("[whatsapp/sync_registration] account=#{account.id} #{e.class}: #{e.message}")
      end

      Rails.logger.info(
        "[whatsapp/sync_registration] checked=#{checked} unregistered=#{unregistered.size} ids=#{unregistered.inspect}"
      )

      return if unregistered.empty?

      SlackNotifyJob.perform_async(
        ":warning: WhatsApp registration sync (#{Rails.env}) — #{unregistered.size} of #{checked} " \
        "connected numbers are NOT registered on Cloud API and will fall back to the shared number. " \
        "account_ids=#{unregistered.inspect}"
      )
    end
  end
end
