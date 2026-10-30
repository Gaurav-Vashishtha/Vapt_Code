# frozen_string_literal: true

require 'test_helper'

class Whatsapp::Inbox::OutboundMirrorTest < ActiveSupport::TestCase
  setup do
    @shop = shops(:regular_shop)
    @account = WhatsappAccount.create!(shop: @shop, waba_id: 'waba-mirror', phone_number_id: SecureRandom.hex(6), status: :verified)
    now = Time.current
    @conversation = WhatsappConversation.create!(shop: @shop, whatsapp_account: @account, customer_wa_id: '919833333333',
                                                 phone_last10: '9833333333', status: :open, status_changed_at: now,
                                                 last_inbound_at: 1.hour.ago, last_message_at: 1.hour.ago)
  end

  def log!(attrs = {})
    WhatsappMessageLog.create!({ shop: @shop, whatsapp_account: @account, event_type_key: 'order_confirmation',
                                 template_name: 'order_confirmed', recipient: '09833333333', status: :queued,
                                 payload_snapshot: { 'body_parameters' => [{ 'type' => 'text', 'text' => 'Aman' }] } }.merge(attrs))
  end

  test 'a sent notification for an existing conversation appears in the thread' do
    log = log!
    assert_nil WhatsappConversationMessage.find_by(whatsapp_message_log_id: log.id)

    log.update!(meta_message_id: 'wamid.MIRROR1', status: :sent, sent_at: Time.current)
    message = WhatsappConversationMessage.find_by(whatsapp_message_log_id: log.id)

    assert message
    assert_equal @conversation.id, message.whatsapp_conversation_id
    assert message.outbound?
    assert_equal 'notification', message.source
    assert_equal 'template', message.kind
    assert_equal 'sent', message.status
    assert_equal ['Aman'], message.content['body_parameters']
    assert @conversation.reload.last_outbound?
    assert_equal 'open', @conversation.status
  end

  test 'resend replaces the meta id on the same thread row' do
    log = log!
    log.update!(meta_message_id: 'wamid.MIRROR2', status: :sent, sent_at: Time.current)
    log.update!(meta_message_id: 'wamid.MIRROR3', status: :sent, sent_at: Time.current)
    rows = WhatsappConversationMessage.where(whatsapp_message_log_id: log.id)
    assert_equal 1, rows.count
    assert_equal 'wamid.MIRROR3', rows.first.meta_message_id
  end

  test 'campaign and payment link sends are labelled by source' do
    campaign_log = log!(whatsapp_campaign_id: 99)
    campaign_log.update!(meta_message_id: 'wamid.CAMP1', status: :sent)
    pay_log = log!(event_type_key: 'cod_to_prepaid')
    pay_log.update!(meta_message_id: 'wamid.PAY1', status: :sent)

    assert_equal 'campaign', WhatsappConversationMessage.find_by(whatsapp_message_log_id: campaign_log.id).source
    assert_equal 99, WhatsappConversationMessage.find_by(whatsapp_message_log_id: campaign_log.id).content['campaign_id']
    assert_equal 'payment_link', WhatsappConversationMessage.find_by(whatsapp_message_log_id: pay_log.id).source
  end

  test 'inbox template logs and unknown customers are not mirrored' do
    inbox_log = log!(event_type_key: 'inbox_template')
    inbox_log.update!(meta_message_id: 'wamid.INBOX1', status: :sent)
    stranger = log!(recipient: '919000000000')
    stranger.update!(meta_message_id: 'wamid.STRANGER1', status: :sent)

    assert_nil WhatsappConversationMessage.find_by(whatsapp_message_log_id: inbox_log.id)
    assert_nil WhatsappConversationMessage.find_by(whatsapp_message_log_id: stranger.id)
  end

  test 'body placeholders are rendered from parameters' do
    template = Struct.new(:components).new([{ 'type' => 'BODY', 'text' => 'Hi {{1}}, order {{2}} is confirmed' }])
    body = Whatsapp::Inbox::OutboundMirror.render_body(template, [{ 'type' => 'text', 'text' => 'Aman' }, '#1001'])
    assert_equal 'Hi Aman, order #1001 is confirmed', body
  end
end
