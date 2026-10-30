# frozen_string_literal: true

require 'test_helper'

class Whatsapp::Inbox::InboundRecorderTest < ActiveSupport::TestCase
  SAMPLES = JSON.parse(File.read(Rails.root.join('test/fixtures/files/meta_inbound_samples.json')))

  setup do
    @shop = shops(:regular_shop)
    @account = WhatsappAccount.create!(shop: @shop, waba_id: 'waba-rec', phone_number_id: SecureRandom.hex(6), status: :verified)
    @enqueued = []
  end

  def inbound!(msg, account: @account, received_at: nil)
    WhatsappInboundMessage.create!(
      shop: account.shop, whatsapp_account: account, meta_message_id: msg['id'], from_phone: msg['from'],
      kind: 'other', received_at: received_at || Time.at(msg['timestamp'].to_i), meta_payload: msg
    )
  end

  def record(inbound, **opts)
    Whatsapp::Inbox::ProcessInboundJob.stub(:perform_async, ->(*args) { @enqueued << [:process, *args] }) do
      Whatsapp::Inbox::BackfillThreadJob.stub(:perform_async, ->(*args) { @enqueued << [:backfill, *args] }) do
        Whatsapp::Inbox::InboundRecorder.call(inbound, **opts)
      end
    end
  end

  test 'first message creates an open conversation with an episode and queues follow-ups' do
    message = record(inbound!(SAMPLES['text']['message']), profile_name: 'Aman')
    conversation = message.whatsapp_conversation

    assert conversation.open?
    assert_equal 'Aman', conversation.customer_name
    assert_equal '919876543210', conversation.customer_wa_id
    assert_equal '9876543210', conversation.phone_last10
    assert_equal 1, conversation.unread_count
    assert_equal 'Where is my order?', conversation.last_message_preview
    assert conversation.last_inbound?
    assert conversation.current_episode
    assert_includes @enqueued, [:process, message.id, true]
    assert_includes @enqueued, [:backfill, conversation.id]
  end

  test 'every sample type lands in one conversation, one row each, idempotently' do
    SAMPLES.each_value do |sample|
      inbound = inbound!(sample['message'])
      2.times { record(inbound) }
    end

    assert_equal 1, WhatsappConversation.where(shop: @shop).count
    conversation = WhatsappConversation.find_by(shop: @shop)
    assert_equal SAMPLES.size, conversation.messages.count
    kinds = conversation.messages.pluck(:kind).uniq.sort
    assert_equal SAMPLES.values.map { |s| s['expect']['kind'] }.uniq.sort, kinds
    assert conversation.messages.where(kind: 'image').first.media_pending?
    assert conversation.messages.where(kind: 'text').first.media_none?
  end

  test 'reactions do not reopen, count as unread or move the window' do
    first = record(inbound!(SAMPLES['text']['message']))
    conversation = first.whatsapp_conversation
    Whatsapp::Inbox::ConversationState.set_status!(conversation, 'resolved')
    before = conversation.reload.last_inbound_at

    record(inbound!(SAMPLES['reaction']['message']))
    conversation.reload
    assert conversation.resolved?
    assert_equal before, conversation.last_inbound_at
    assert_equal 1, conversation.unread_count
  end

  test 'a reaction alone never starts a conversation' do
    assert_nil record(inbound!(SAMPLES['reaction']['message']))
    assert_equal 0, WhatsappConversation.where(shop: @shop).count
  end

  test 'a new message reopens a resolved conversation with a new episode' do
    conversation = record(inbound!(SAMPLES['text']['message'])).whatsapp_conversation
    Whatsapp::Inbox::ConversationState.set_status!(conversation, 'resolved')
    old_episode_id = conversation.reload.current_episode_id

    record(inbound!(SAMPLES['image']['message']))
    conversation.reload
    assert conversation.open?
    refute_equal old_episode_id, conversation.current_episode_id
    assert_equal 2, conversation.episodes.count
  end

  test 'older messages arriving late do not replace the latest preview or window' do
    record(inbound!(SAMPLES['image']['message'], received_at: Time.current))
    late = SAMPLES['text']['message'].merge('id' => 'wamid.LATE1')
    record(inbound!(late, received_at: 2.days.ago))
    conversation = WhatsappConversation.find_by(shop: @shop)
    assert_equal 'Damaged box', conversation.last_message_preview
    assert_equal 'wamid.IMAGE1', conversation.last_inbound_meta_message_id
  end

  test 'backfill mode skips unread, state changes and jobs' do
    message = record(inbound!(SAMPLES['text']['message']), backfill: true)
    conversation = message.whatsapp_conversation
    assert_equal 0, conversation.unread_count
    assert_nil conversation.current_episode_id
    assert_empty @enqueued
  end

  test 'custom-branded numbers are skipped' do
    inbound = inbound!(SAMPLES['text']['message'])
    inbound.whatsapp_account.shop_id = nil
    assert_nil record(inbound)
  end

  test 'kill switch disables recording' do
    ENV['WHATSAPP_INBOX_DISABLED'] = '1'
    assert_nil record(inbound!(SAMPLES['text']['message']))
  ensure
    ENV.delete('WHATSAPP_INBOX_DISABLED')
  end
end
