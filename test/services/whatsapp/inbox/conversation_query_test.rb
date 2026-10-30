# frozen_string_literal: true

require 'test_helper'

class Whatsapp::Inbox::ConversationQueryTest < ActiveSupport::TestCase
  setup do
    @shop = shops(:regular_shop)
    @other = Shop.find(Shop.insert({ shopify_domain: 'query-other.myshopify.com', shopify_token: 'token',
                                     created_at: Time.current, updated_at: Time.current }, returning: :id).rows.first.first)
    @account = account!(@shop)
    @agent = WhatsappInboxAgent.create!(shop: @shop, shopify_user_id: 42, name: 'Asha')
  end

  def account!(shop)
    WhatsappAccount.create!(shop: shop, waba_id: "waba-#{SecureRandom.hex(3)}", phone_number_id: SecureRandom.hex(6),
                            status: :verified)
  end

  def conversation!(shop, account, wa_id, attrs = {})
    at = attrs.delete(:at) || 1.hour.ago
    WhatsappConversation.create!({ shop: shop, whatsapp_account: account, customer_wa_id: wa_id,
                                   phone_last10: wa_id.last(10), status: :open, status_changed_at: at,
                                   last_inbound_at: at, last_message_at: at }.merge(attrs))
  end

  def query(params = {}, agent: @agent)
    Whatsapp::Inbox::ConversationQuery.call(shop: @shop, agent: agent, params: params)
  end

  test 'lists only this shop, open by default, newest customer message first' do
    older = conversation!(@shop, @account, '919800000001', at: 3.hours.ago)
    newer = conversation!(@shop, @account, '919800000002', at: 1.hour.ago)
    conversation!(@shop, @account, '919800000003', status: :resolved)
    conversation!(@other, account!(@other), '919800000004')

    result = query
    assert_equal [newer.id, older.id], result[:conversations].map(&:id)
    assert_nil result[:next_cursor]
    assert_equal({ 'open' => 2, 'pending' => 0, 'resolved' => 1, 'unread' => 0 }, result[:counts])
  end

  test 'status all and assignee filters' do
    mine = conversation!(@shop, @account, '919800000011', assignee_agent: @agent, status: :pending)
    free = conversation!(@shop, @account, '919800000012')

    assert_equal [mine.id], query(status: 'all', assignee: 'me')[:conversations].map(&:id)
    assert_equal [free.id], query(status: 'all', assignee: 'unassigned')[:conversations].map(&:id)
    assert_equal [mine.id], query(status: 'all', assignee: @agent.id.to_s)[:conversations].map(&:id)
    assert_empty query(status: 'all', assignee: 'me', agent: nil)[:conversations]
  end

  test 'label filter is scoped to the shop' do
    tagged = conversation!(@shop, @account, '919800000021')
    conversation!(@shop, @account, '919800000022')
    label = WhatsappInboxLabel.create!(shop: @shop, name: 'VIP', color: 'info')
    WhatsappConversationLabel.create!(shop: @shop, whatsapp_conversation: tagged, whatsapp_inbox_label: label, source: 'agent')

    assert_equal [tagged.id], query(label_id: label.id.to_s)[:conversations].map(&:id)
  end

  test 'search by name, phone digits and order number' do
    by_name = conversation!(@shop, @account, '919800000031', customer_name: 'Ravi Kumar')
    by_phone = conversation!(@shop, @account, '919811112222')
    by_order = conversation!(@shop, @account, '919833334444')
    OrderConfirmation.create!(shop: @shop, customer_number: '+91 98333 34444', order_number: '#5521', status: 'COD-Verified')

    assert_equal [by_name.id], query(q: 'ravi')[:conversations].map(&:id)
    assert_equal [by_phone.id], query(q: '+91 98111 12222')[:conversations].map(&:id)
    assert_includes query(q: '#5521')[:conversations].map(&:id), by_order.id
    assert_empty query(q: '%')[:conversations]
  end

  test 'keyset pagination returns every row exactly once' do
    base = 2.days.ago
    ids = 35.times.map { |i| conversation!(@shop, @account, format('9198%08d', i), at: base + i.minutes).id }

    first = query
    assert_equal 30, first[:conversations].size
    assert first[:next_cursor].present?
    second = query(cursor: first[:next_cursor])
    assert_nil second[:next_cursor]
    assert_equal ids.reverse, (first[:conversations] + second[:conversations]).map(&:id)
  end

  test 'cursor round-trips with microsecond precision' do
    t = Time.zone.at(Rational('1760600000.123456'))
    encoded = Whatsapp::Inbox::ConversationQuery.encode_cursor(t, 7)
    assert_equal [t, 7], Whatsapp::Inbox::ConversationQuery.decode_cursor(encoded)
    assert_nil Whatsapp::Inbox::ConversationQuery.decode_cursor("1'; DROP TABLE x;--_1")
  end
end
