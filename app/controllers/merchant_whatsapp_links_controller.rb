# frozen_string_literal: true

class MerchantWhatsappLinksController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false

  def callback
    domain = params[:shop].to_s.strip
    shop = Shop.find_by(shopify_domain: domain)

    record = CallbackRequest.new(
      shop_domain: domain,
      phone_number: params[:phone].presence || shop&.owner_phone,
      email: shop&.owner_email,
      name: shop&.shop_owner.presence || shop&.owner_name,
      notes: "Requested via WhatsApp"
    )

    if record.save
      CallbackMailer.notify_approvers(record.id).deliver_later rescue nil
      shop&.setting&.update(last_callback_request_at: Time.current) rescue nil
    end

    render html: confirmation_page("Thanks! Our team will call you back shortly.").html_safe
  rescue => e
    Rails.logger.error("[mwa/callback] #{e.class}: #{e.message}")
    render html: confirmation_page("We've received your request.").html_safe
  end

  def chat
    shop = Shop.find_by(shopify_domain: params[:shop].to_s.strip)
    url = shop&.crisp_url
    return redirect_to url, allow_other_host: true if url.present?

    render html: confirmation_page("Chat is unavailable for this store right now.").html_safe, status: :not_found
  end

  private

  def confirmation_page(message)
    "<!DOCTYPE html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'>" \
      "<title>COD King</title></head><body style='font-family:-apple-system,sans-serif;text-align:center;padding:48px 24px;color:#111;'>" \
      "<h2 style='margin-bottom:8px;'>COD King</h2><p style='color:#555;'>#{ERB::Util.html_escape(message)}</p></body></html>"
  end
end
