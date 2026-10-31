class LeadCollectionMailer < ApplicationMailer
  def notify_whatsapp_approvers(lead_collection_id)
    @lead = LeadCollection.find(lead_collection_id)
    approver_emails = ENV.fetch("WHATSAPP_APPROVERS_EMAIL_LIST", nil).to_s
      .split(",")
      .map(&:strip)
      .reject(&:blank?)
    approver_emails = ["support@notifiktech.com"] if approver_emails.blank?

    mail(
      to: approver_emails,
      subject: "New Lead Collection Request - #{@lead.phone_number}"
    )
  end

  def notify_one_click_checkout_interest(lead_collection_id, shop_id)
    @lead = LeadCollection.find(lead_collection_id)
    @shop = Shop.find_by(id: shop_id)
    @shop_created_date = format_shop_created_date(@shop)

    recipient_emails = ENV.fetch("ONE_CLICK_CHECKOUT_EMAIL_LIST", nil).to_s
      .split(",")
      .map(&:strip)
      .reject(&:blank?)
    if recipient_emails.blank?
      recipient_emails = ["adbhatia1989@gmail.com", "avijeetdey.email@gmail.com"]
    end

    mail(
      to: recipient_emails,
      subject: "One-Click Checkout Interest - #{@shop&.shopify_domain || @lead.website}"
    )
  end

  def notify_rabbit_express_interest(lead_collection_id, shop_id)
    @lead = LeadCollection.find(lead_collection_id)
    @shop = Shop.find_by(id: shop_id)
    @shop_created_date = format_shop_created_date(@shop)

    recipient_emails = ENV.fetch("RABBIT_EXPRESS_EMAIL_LIST", nil).to_s
      .split(",")
      .map(&:strip)
      .reject(&:blank?)
    if recipient_emails.blank?
      recipient_emails = ["adbhatia1989@gmail.com", "avijeetdey.email@gmail.com"]
    end

    mail(
      to: recipient_emails,
      subject: "Rabbit Express Interest - #{@shop&.shopify_domain || @lead.website}"
    )
  end

  private

  def format_shop_created_date(shop)
    raw = shop&.shop_created_date
    return nil if raw.blank?

    Date.parse(raw.to_s).strftime("%B %d, %Y")
  rescue ArgumentError
    raw
  end
end
