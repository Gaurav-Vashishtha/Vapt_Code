# frozen_string_literal: true

class WhatsappInboxMailer < ApplicationMailer
  layout 'mailer'

  helper_method :copy

  def unanswered(conversation_id)
    @conversation = WhatsappConversation.find_by(id: conversation_id)
    return if @conversation.nil?

    @shop = @conversation.shop
    return if @shop.nil?

    recipient = recipient_email
    return if recipient.blank?

    @customer = @conversation.customer_name.presence || "+#{@conversation.customer_wa_id}"
    @minutes = [((Time.current - @conversation.last_inbound_at) / 60).floor, 1].max
    @preview = latest_customer_text.to_s.truncate(200)
    @inbox_url = inbox_url

    mail(to: recipient, subject: copy('subject', customer: @customer))
  end

  private

  DEFAULTS = {
    'subject' => '%{customer} is waiting for a reply on WhatsApp',
    'heading' => 'A customer has been waiting %{minutes} minutes',
    'body' => '%{customer} wrote: "%{preview}"',
    'cta' => 'Open the inbox'
  }.freeze

  def copy(key, **vars)
    I18n.t("whatsapp_inbox_mailer.unanswered.#{key}", default: DEFAULTS.fetch(key), **vars)
  end

  def recipient_email
    assignee = @conversation.assignee_agent
    assignee&.email.presence || @shop.owner_email.presence
  end

  def latest_customer_text
    WhatsappConversationMessage.where(whatsapp_conversation_id: @conversation.id, direction: :inbound)
                               .where.not(body: [nil, ''])
                               .order(occurred_at: :desc, id: :desc)
                               .pick(:body) || @conversation.last_message_preview
  end

  def inbox_url
    key = ENV.fetch('SHOPIFY_API_KEY', '').to_s.strip
    base = "https://#{@shop.shopify_domain}/admin/apps"
    key.present? ? "#{base}/#{key}/features/whatsapp/inbox/#{@conversation.id}" : base
  end
end
