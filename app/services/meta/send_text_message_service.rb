module Meta
  # Sends a free-form (non-template) WhatsApp text message. Only valid inside
  # the 24-hour customer-service window — i.e. after the customer has messaged
  # us (e.g. tapped a quick-reply button). Outside that window Meta rejects it
  # with error 131047. Returns the Meta message id on success.
  #
  #   Meta::SendTextMessageService.call(account: acct, recipient: "9199...", body: "…")
  class SendTextMessageService < ApplicationService
    class Error < StandardError; end

    def initialize(account:, recipient:, body:)
      @account = account
      @recipient = recipient
      @body = body
    end

    def call
      raise Error, 'account is not ready to send' unless account.ready_to_send?
      raise Error, 'recipient is required' if recipient.blank?
      raise Error, 'body is required' if body.blank?

      payload = {
        messaging_product: 'whatsapp',
        recipient_type: 'individual',
        to: normalize_phone(recipient),
        type: 'text',
        text: { preview_url: false, body: body.to_s }
      }

      response = account.graph_client.post("#{account.phone_number_id}/messages", body: payload)
      response.dig('messages', 0, 'id')
    rescue Meta::GraphClient::Error => e
      raise Error, e.message
    end

    private

    attr_reader :account, :recipient, :body

    def normalize_phone(value)
      value.to_s.gsub(/\D/, '').sub(/\A0+/, '')
    end
  end
end
