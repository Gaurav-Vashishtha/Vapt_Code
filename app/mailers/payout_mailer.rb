# frozen_string_literal: true

class PayoutMailer < ApplicationMailer
  def payout_completed_to_partner(payout)
    @payout = payout
    @partner = payout.referral_partner
    @amount = payout.total_amount
    @payout_date = payout.payout_date
    @payment_method = payout.payment_method

    mail(
      to: @partner.email,
      subject: "Your COD King Referral Payout Completed - $#{format('%.2f', payout.total_amount)}"
    )
  end

  def payout_completed_to_admin(payout)
    @payout = payout
    @partner = payout.referral_partner
    @amount = payout.total_amount
    @payout_date = payout.payout_date
    @payment_method = payout.payment_method

    admin_emails = ENV['WHATSAPP_APPROVERS_EMAIL_LIST'].to_s.strip
    return if admin_emails.blank?

    mail(
      to: admin_emails.split(',').map(&:strip),
      subject: "Referral Payout Processed: #{@partner.name} - $#{format('%.2f', payout.total_amount)}"
    )
  end
end
