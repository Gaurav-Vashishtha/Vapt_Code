module NetworkJobs
  # NetworkJobs::PrepaidScheduleJob.perform_async(Shop.last.id,OrderConfirmation.last.id)
  #
  # Schedule order:
  #   1. If setting.prepaid_reminders has any matching reminder for this order's
  #      cart total → fan out one SendPrepaidSmsJob per match, each with its own
  #      delay + reminder_id (the send job resolves per-reminder overrides).
  #   2. Else fall back to the legacy setting.prepaid_schedule comma-separated
  #      minutes list.
  #   3. Else single immediate send.
  class PrepaidScheduleJob < ApplicationJob
    def perform(shop_id, order_confirmation_id)
      shop = Shop.find(shop_id)
      order_confirmation = OrderConfirmation.find(order_confirmation_id)
      return unless order_confirmation.is_cod_order

      matching = shop.setting.matching_prepaid_reminders(order_confirmation.order_amount)

      if matching.any?
        matching.each do |reminder|
          delay_seconds = reminder['delay_minutes'].to_i.minutes
          NetworkJobs::SendPrepaidSmsJob.perform_in(
            delay_seconds, shop.id, order_confirmation.id, reminder['id']
          )
        end
      elsif shop.setting.prepaid_schedule.present?
        shop.setting.prepaid_schedule.split(',').each do |schedule|
          mins = schedule.to_i
          next unless mins > 0
          # The slot token becomes the send's dedup key on the BSP path — without
          # it every slot for one order shares a key and the unique index on
          # whatsapp_message_logs drops all but the first send.
          NetworkJobs::SendPrepaidSmsJob.perform_in(
            mins.minutes, shop.id, order_confirmation.id, nil, "schedule-#{mins}"
          )
        end
      else
        NetworkJobs::SendPrepaidSmsJob.perform_async(shop.id, order_confirmation.id)
      end
    end
  end
end

