# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class Api::Whatsapp::Inbox::ConversationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    ShopifyApp.configuration.api_key ||= 'test-api-key'
    ShopifyApp.configuration.secret ||= 'test-api-secret'
    @shop = shops(:regular_shop)
    @other = Shop.find(Shop.insert({ shopify_domain: 'conv-other.myshopify.com', shopify_token: 'token',
                                     created_at: Time.current, updated_at: Time.current }, returning: :id).rows.first.first)
    @account = account!(@shop)
    @conversation = conversation!(@shop, @account, '919876543210', customer_name: 'Meera', unread_count: 2,
                                                                   last_inbound_meta_message_id: 'wamid.in1')
    @foreign = conversation!(@other, account!(@other), '919876543210')
  end

  def account!(shop)
    WhatsappAccount.create!(shop: shop, waba_id: "waba-#{SecureRandom.hex(3)}", phone_number_id: SecureRandom.hex(6),
                            status: :verified)
  end

  def conversation!(shop, account, wa_id, attrs = {})
    WhatsappConversation.create!({ shop: shop, whatsapp_account: account, customer_wa_id: wa_id,
                                   phone_last10: wa_id.last(10), status: :open, status_changed_at: 1.hour.ago,
                                   last_inbound_at: 1.hour.ago, last_message_at: 1.hour.ago }.merge(attrs))
  end

  def headers(shop = @shop, sub: '42')
    now = Time.now.to_i
    payload = { iss: "https://#{shop.shopify_domain}/admin", dest: "https://#{shop.shopify_domain}",
                aud: ShopifyApp.configuration.api_key, sub: sub, exp: now + 300, nbf: now - 60, iat: now,
                jti: SecureRandom.uuid, sid: SecureRandom.hex(8) }
    { 'Authorization' => "Bearer #{JWT.encode(payload, ShopifyApp.configuration.secret, 'HS256')}" }
  end

  def json
    JSON.parse(response.body)
  end

  test 'index returns only this shop with the documented shape' do
    get '/api/whatsapp/inbox/conversations', headers: headers
    assert_response :success

    assert_equal [@conversation.id], json['conversations'].map { |c| c['id'] }
    row = json['conversations'].first
    assert_equal %w[account assignee customer id labels last_inbound_at last_message opted_out status unread_count
                    window_expires_at window_open].sort, row.keys.sort
    assert_equal '+91 98765 43210', row.dig('customer', 'phone_display')
    assert json.key?('next_cursor')
    assert_equal 1, json.dig('counts', 'open')
  end

  test 'another shop conversation is not found' do
    get "/api/whatsapp/inbox/conversations/#{@foreign.id}", headers: headers
    assert_response :not_found
    assert_equal 'not_found', json['code']
  end

  test 'show returns detail fields' do
    get "/api/whatsapp/inbox/conversations/#{@conversation.id}", headers: headers
    assert_response :success
    detail = json['conversation']
    %w[note status_changed_at episode variables].each { |k| assert detail.key?(k), k }
  end

  test 'update assigns, writes the note and changes status' do
    agent = WhatsappInboxAgent.create!(shop: @shop, shopify_user_id: 77, name: 'Kiran')
    patch "/api/whatsapp/inbox/conversations/#{@conversation.id}",
          params: { assignee_id: agent.id, note: 'Wants a refund', status: 'pending' }, headers: headers, as: :json
    assert_response :success
    @conversation.reload
    assert_equal agent.id, @conversation.assignee_agent_id
    assert_equal 'Wants a refund', @conversation.note
    assert @conversation.pending?
    assert_equal 'Kiran', json.dig('conversation', 'assignee', 'name')
  end

  test 'update rejects an agent from another shop' do
    stranger = WhatsappInboxAgent.create!(shop: @other, shopify_user_id: 99)
    patch "/api/whatsapp/inbox/conversations/#{@conversation.id}",
          params: { assignee_id: stranger.id }, headers: headers, as: :json
    assert_response :unprocessable_entity
    assert_equal 'invalid', json['code']
    assert_nil @conversation.reload.assignee_agent_id
  end

  test 'read clears unread and queues the read receipt; unread restores one' do
    queued = []
    Whatsapp::Inbox::MarkReadJob.stub(:perform_async, ->(id) { queued << id }) do
      post "/api/whatsapp/inbox/conversations/#{@conversation.id}/read", headers: headers
    end
    assert_response :success
    assert_equal 0, @conversation.reload.unread_count
    assert_equal [@conversation.id], queued

    post "/api/whatsapp/inbox/conversations/#{@conversation.id}/unread", headers: headers
    assert_equal 1, @conversation.reload.unread_count
  end

  test 'block and unblock toggle the opt-out for this shop only' do
    post "/api/whatsapp/inbox/conversations/#{@conversation.id}/block", headers: headers
    assert_equal true, json['opted_out']
    assert WhatsappOptOut.opted_out?(@shop.id, '919876543210')
    refute WhatsappOptOut.opted_out?(@other.id, '919876543210')

    post "/api/whatsapp/inbox/conversations/#{@conversation.id}/unblock", headers: headers
    assert_equal false, json['opted_out']
  end

  test 'agent identity falls back to the store team without a staff id' do
    get '/api/whatsapp/inbox/me', headers: headers(sub: '')
    assert_response :success
    assert_equal true, json.dig('agent', 'is_store_team')
    assert_equal true, json.dig('agent', 'is_me')
  end
end
