# frozen_string_literal: true

class ParcelxMailer < ApplicationMailer
  def low_credits(credits, threshold)
    @credits = credits
    @threshold = threshold
    @checked_at = Time.current

    mail(
      to: recipients,
      subject: "ParcelX credits low — #{ActiveSupport::NumberHelper.number_to_delimited(credits)} left"
    )
  end

  private

  def recipients
    ENV['WHATSAPP_APPROVERS_EMAIL_LIST'].presence || 'support@notifiktech.com'
  end
end
