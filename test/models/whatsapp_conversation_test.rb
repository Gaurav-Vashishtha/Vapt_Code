# frozen_string_literal: true

require 'test_helper'

class WhatsappConversationTest < ActiveSupport::TestCase
  test 'phone_last10 keeps the last ten digits' do
    assert_equal '9876543210', WhatsappConversation.phone_last10('+91 98765-43210')
    assert_equal '12345', WhatsappConversation.phone_last10('12345')
    assert_equal '', WhatsappConversation.phone_last10(nil)
  end

  test 'window is open for 24 hours after the last customer message' do
    now = Time.current
    conversation = WhatsappConversation.new(last_inbound_at: now - 23.hours)
    assert conversation.window_open?(now)
    assert_equal now + 1.hour, conversation.window_expires_at

    conversation.last_inbound_at = now - 24.hours
    refute conversation.window_open?(now)
  end

  test 'a 131047 hint closes the window until the customer writes again' do
    now = Time.current
    conversation = WhatsappConversation.new(last_inbound_at: now - 2.hours, window_closed_hint_at: now - 1.hour)
    refute conversation.window_open?(now)

    conversation.last_inbound_at = now - 10.minutes
    assert conversation.window_open?(now)
  end

  test 'no inbound means no window' do
    refute WhatsappConversation.new.window_open?
    assert_nil WhatsappConversation.new.window_expires_at
  end

  test 'message status only moves forward, failed always wins' do
    shop = shops(:regular_shop)
    account = WhatsappAccount.create!(shop: shop, waba_id: 'waba-model', phone_number_id: SecureRandom.hex(6), status: :verified)
    conversation = WhatsappConversation.create!(shop: shop, whatsapp_account: account, customer_wa_id: '919811111111',
                                                phone_last10: '9811111111', status_changed_at: Time.current,
                                                last_inbound_at: Time.current, last_message_at: Time.current)
    message = WhatsappConversationMessage.create!(whatsapp_conversation: conversation, shop: shop, direction: :outbound,
                                                  source: 'agent', kind: 'text', body: 'hi', status: :sent,
                                                  occurred_at: Time.current, meta_message_id: 'wamid.MODEL1')

    assert message.advance_status!('read', at: Time.current)
    refute message.advance_status!('delivered', at: Time.current)
    assert_equal 'read', message.reload.status

    assert message.advance_status!('failed', at: Time.current, error: { 'code' => 131_026, 'title' => 'Undeliverable' })
    message.reload
    assert message.delivery_failed?
    assert_equal '131026', message.error_code
  end
end
