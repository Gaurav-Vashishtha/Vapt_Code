# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class Api::Whatsapp::Inbox::MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    ShopifyApp.configuration.api_key ||= 'test-api-key'
    ShopifyApp.configuration.secret ||= 'test-api-secret'
    @shop = shops(:regular_shop)
    @account = WhatsappAccount.create!(shop: @shop, waba_id: 'waba-msg', phone_number_id: SecureRandom.hex(6), status: :verified)
    @conversation = WhatsappConversation.create!(shop: @shop, whatsapp_account: @account, customer_wa_id: '919876543210',
                                                 phone_last10: '9876543210', status: :open, status_changed_at: 1.hour.ago,
                                                 last_inbound_at: 1.hour.ago, last_message_at: 1.hour.ago)
  end

  def headers
    now = Time.now.to_i
    payload = { iss: "https://#{@shop.shopify_domain}/admin", dest: "https://#{@shop.shopify_domain}",
                aud: ShopifyApp.configuration.api_key, sub: '42', exp: now + 300, nbf: now - 60, iat: now,
                jti: SecureRandom.uuid, sid: SecureRandom.hex(8) }
    { 'Authorization' => "Bearer #{JWT.encode(payload, ShopifyApp.configuration.secret, 'HS256')}" }
  end

  def message!(at, attrs = {})
    WhatsappConversationMessage.create!({ whatsapp_conversation: @conversation, shop: @shop, direction: :inbound,
                                          source: 'customer', kind: 'text', body: "hi #{at.to_i}", occurred_at: at }.merge(attrs))
  end

  def json
    JSON.parse(response.body)
  end

  def path(suffix = '')
    "/api/whatsapp/inbox/conversations/#{@conversation.id}/messages#{suffix}"
  end

  test 'index pages backwards in chronological order' do
    rows = 55.times.map { |i| message!(2.days.ago + i.minutes) }

    get path, headers: headers
    assert_response :success
    assert_equal rows.last(50).map(&:id), json['messages'].map { |m| m['id'] }
    assert_equal true, json['has_more']
    assert json['server_time'].present?
    assert json['conversation'].present?

    get path("?before=#{rows[5].id}"), headers: headers
    assert_equal rows.first(5).map(&:id), json['messages'].map { |m| m['id'] }
    assert_equal false, json['has_more']
  end

  test 'since returns only rows changed after the poll time' do
    message!(1.hour.ago).update_column(:updated_at, 1.hour.ago)
    fresh = message!(1.minute.ago)

    get path("?since=#{CGI.escape(30.minutes.ago.iso8601)}"), headers: headers
    assert_equal [fresh.id], json['messages'].map { |m| m['id'] }

    get path('?since=yesterday'), headers: headers
    assert_response :bad_request
  end

  test 'text reply goes through the free-form sender as the agent' do
    sent = message!(Time.current, direction: :outbound, source: 'agent', status: :sent)
    captured = nil
    sender = lambda do |**kw|
      captured = kw
      sent
    end
    Whatsapp::Inbox::FreeformSender.stub(:call, sender) do
      post path, params: { type: 'text', text: 'On its way!', resolve: true }, headers: headers, as: :json
    end
    assert_response :created
    assert_equal sent.id, json.dig('message', 'id')
    assert_equal 'agent', captured[:source]
    assert_equal true, captured[:resolve]
    assert_equal 'On its way!', captured[:text]
  end

  test 'window closed maps to the window_closed code' do
    closed = ->(**) { raise Whatsapp::Inbox::FreeformSender::WindowClosed, 'closed' }
    Whatsapp::Inbox::FreeformSender.stub(:call, closed) do
      post path, params: { type: 'text', text: 'hello' }, headers: headers, as: :json
    end
    assert_response :unprocessable_entity
    assert_equal 'window_closed', json['code']
  end

  test 'send failures carry the Meta error code' do
    failed = ->(**) { raise Whatsapp::Inbox::FreeformSender::SendFailed.new('Rate limited', 131056) }
    Whatsapp::Inbox::FreeformSender.stub(:call, failed) do
      post path, params: { type: 'text', text: 'hello' }, headers: headers, as: :json
    end
    assert_equal 'send_failed', json['code']
    assert_equal 131056, json['meta_code']
  end

  test 'a template from another number is refused' do
    other_account = WhatsappAccount.create!(shop: @shop, waba_id: 'waba-2', phone_number_id: SecureRandom.hex(6), status: :verified)
    template = WhatsappTemplate.create!(whatsapp_account: other_account, name: 'hello_again', language: 'en', category: 'UTILITY',
                                        status: :approved, components: [{ 'type' => 'BODY', 'text' => 'Hi {{1}}' }])
    post path, params: { type: 'template', template_id: template.id, body_parameters: ['Aman'] }, headers: headers, as: :json
    assert_response :unprocessable_entity
    assert_equal 'template_invalid', json['code']
  end

  test 'template parameters must fill every placeholder' do
    template = WhatsappTemplate.create!(whatsapp_account: @account, name: 'order_help', language: 'en', category: 'UTILITY',
                                        status: :approved, components: [{ 'type' => 'BODY', 'text' => 'Hi {{1}}, order {{2}}' }])
    post path, params: { type: 'template', template_id: template.id, body_parameters: ['Aman'] }, headers: headers, as: :json
    assert_equal 'template_invalid', json['code']
  end

  test 'unknown type is invalid' do
    post path, params: { type: 'sticker' }, headers: headers, as: :json
    assert_equal 'invalid', json['code']
  end
end
