# frozen_string_literal: true

require 'test_helper'

class Whatsapp::Inbox::FreeformSenderTest < ActiveSupport::TestCase
  Sender = Whatsapp::Inbox::FreeformSender

  class FakeClient
    attr_reader :posts

    def initialize(response: nil, error: nil)
      @response = response || { 'messages' => [{ 'id' => "wamid.OUT#{SecureRandom.hex(4)}" }] }
      @error = error
      @posts = []
    end

    def post(path, body: {})
      @posts << [path, body]
      raise @error if @error

      @response
    end
  end

  setup do
    @shop = shops(:regular_shop)
    @account = WhatsappAccount.create!(shop: @shop, waba_id: 'waba-free', phone_number_id: 'pn-free-1', status: :verified)
    @agent = WhatsappInboxAgent.create!(shop: @shop, shopify_user_id: 9, name: 'Dev')
    now = Time.current
    @conversation = WhatsappConversation.create!(shop: @shop, whatsapp_account: @account, customer_wa_id: '919844444444',
                                                 phone_last10: '9844444444', status: :open, status_changed_at: now,
                                                 last_inbound_at: 1.hour.ago, last_message_at: 1.hour.ago,
                                                 last_inbound_meta_message_id: 'wamid.IN1')
    Whatsapp::Inbox::ConversationState.on_inbound!(@conversation, at: 1.hour.ago)
  end

  def send_with(client, **args)
    Meta::GraphClient.stub(:new, client) do
      Sender.call(conversation: @conversation, agent: @agent, source: 'agent', **args)
    end
  end

  test 'text reply is sent, stored in the thread only and moves the ticket to pending' do
    client = FakeClient.new
    message = nil
    assert_no_difference -> { WhatsappMessageLog.count } do
      message = send_with(client, text: 'Your order ships today', reply_to_meta_message_id: 'wamid.IN1')
    end

    path, body = client.posts.first
    assert_equal 'pn-free-1/messages', path
    assert_equal 'text', body[:type]
    assert_equal '919844444444', body[:to]
    assert_equal({ message_id: 'wamid.IN1' }, body[:context])
    assert message.delivery_sent?
    assert message.meta_message_id.present?
    assert_equal @agent.id, message.agent_id
    assert @conversation.reload.pending?
    assert @conversation.current_episode.first_response_at
    assert_equal 'Your order ships today', @conversation.last_message_preview
  end

  test 'closed window raises before calling Meta' do
    @conversation.update!(last_inbound_at: 25.hours.ago)
    client = FakeClient.new
    assert_raises(Sender::WindowClosed) { send_with(client, text: 'hi') }
    assert_empty client.posts
  end

  test 'Meta 131047 marks the message failed and closes the window' do
    error = Meta::GraphClient::Error.new('Re-engagement message', status: 400, body: { 'error' => { 'code' => 131_047 } })
    assert_raises(Sender::WindowClosed) { send_with(FakeClient.new(error: error), text: 'hi') }

    message = @conversation.messages.outbound.last
    assert message.delivery_failed?
    assert_equal '131047', message.error_code
    refute @conversation.reload.window_open?
  end

  test 'other Meta errors raise SendFailed with the meta code' do
    error = Meta::GraphClient::Error.new('Spam', status: 400, body: { 'error' => { 'code' => 131_048 } })
    raised = assert_raises(Sender::SendFailed) { send_with(FakeClient.new(error: error), text: 'hi') }
    assert_equal 131_048, raised.meta_code
  end

  test 'auto replies do not change status' do
    Meta::GraphClient.stub(:new, FakeClient.new) do
      Sender.call(conversation: @conversation, agent: nil, source: 'auto_reply', text: 'Thanks!')
    end
    assert @conversation.reload.open?
  end

  test 'validates text, files and readiness' do
    assert_raises(Sender::Invalid) { send_with(FakeClient.new, text: '  ') }
    assert_raises(Sender::Invalid) { send_with(FakeClient.new, text: 'x' * 4097) }
    upload = { io: StringIO.new('GIF89a'), filename: 'a.gif', content_type: 'image/gif', byte_size: 6 }
    assert_raises(Sender::Invalid) { send_with(FakeClient.new, upload: upload) }
    @account.update!(status: :disabled)
    assert_raises(Sender::NotReady) { send_with(FakeClient.new, text: 'hi') }
  end

  test 'image upload is sent by media id with a caption' do
    client = FakeClient.new
    upload = { io: StringIO.new("\xFF\xD8\xFFjpeg".b), filename: 'photo.jpg', content_type: 'image/jpeg', byte_size: 7 }
    message = Meta::MessagesMediaUploadService.stub(:call, 'media-123') do
      send_with(client, upload: upload, caption: 'Here it is')
    end

    body = client.posts.first.last
    assert_equal 'image', body[:type]
    assert_equal({ id: 'media-123', caption: 'Here it is' }, body[:image])
    assert_equal 'media-123', message.reload.media_id
    assert_equal 'image', message.kind
  end
end
