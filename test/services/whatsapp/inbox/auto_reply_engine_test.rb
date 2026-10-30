# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class Whatsapp::Inbox::AutoReplyEngineTest < ActiveSupport::TestCase
  Engine = Whatsapp::Inbox::AutoReplyEngine

  Message = Struct.new(:id, :shop_id, :whatsapp_conversation_id, :kind, :body, :content, :occurred_at,
                       keyword_init: true) do
    def inbound?
      true
    end
  end

  Account = Struct.new(:ready, :verified_name) do
    def ready_to_send?
      ready
    end
  end

  Conversation = Struct.new(:id, :shop, :phone_last10, :customer_name, :whatsapp_account, :last_agent_reply_at,
                            :last_auto_reply_at, :open_window, keyword_init: true) do
    def window_open?(_now = Time.current)
      open_window
    end
  end

  NoRows = Class.new do
    def where(*)
      self
    end

    def exists?
      false
    end
  end

  setup do
    @now = Time.zone.parse('2026-10-19 10:00:00 UTC')
    @sent = []
  end

  def conversation(**attrs)
    Conversation.new(id: 7, shop: nil, phone_last10: '9876543210', customer_name: 'Aman',
                     whatsapp_account: Account.new(true, 'Glow'), open_window: true, **attrs)
  end

  def message(body: 'hello', kind: 'text', content: {}, occurred_at: nil)
    Message.new(id: 1, shop_id: 1, whatsapp_conversation_id: 7, kind: kind, body: body, content: content,
                occurred_at: occurred_at || @now - 1.minute)
  end

  def setting(**attrs)
    WhatsappInboxSetting.new({ welcome_text: 'Welcome!', away_text: 'We are away', business_hours: {} }.merge(attrs))
  end

  def track_rule(match: 'contains', enabled: true)
    { 'id' => 'r1', 'keywords' => ['track', 'order status'], 'match' => match,
      'reply_text' => 'Track here', 'enabled' => enabled }
  end

  def run_engine(msg, setting:, conversation: self.conversation, created: false, claim: true)
    sender = ->(**kwargs) { @sent << kwargs; :sent }
    WhatsappConversation.stub(:find_by, conversation) do
      WhatsappConversationMessage.stub(:where, NoRows.new) do
        Engine.stub(:claim!, claim) do
          Whatsapp::Inbox::FreeformSender.stub(:call, sender) do
            Engine.call(msg, conversation_created: created, setting: setting, now: @now)
          end
        end
      end
    end
  end

  test 'everything is off by default' do
    assert_nil run_engine(message, setting: setting, created: true)
    assert_empty @sent
  end

  test 'a keyword rule replies with source auto_reply and no agent' do
    run_engine(message(body: 'Where is my ORDER   status?'), setting: setting(keyword_rules: [track_rule]))
    assert_equal 1, @sent.size
    assert_equal 'auto_reply', @sent.first[:source]
    assert_nil @sent.first[:agent]
    assert_equal 'Track here', @sent.first[:text]
  end

  test 'contains matches whole words only; exact needs the whole message' do
    run_engine(message(body: 'tracking please'), setting: setting(keyword_rules: [track_rule]))
    assert_empty @sent

    run_engine(message(body: 'track my parcel'), setting: setting(keyword_rules: [track_rule(match: 'exact')]))
    assert_empty @sent

    run_engine(message(body: 'Track!'), setting: setting(keyword_rules: [track_rule(match: 'exact')]))
    assert_equal 1, @sent.size
  end

  test 'disabled rules are ignored' do
    run_engine(message(body: 'track'), setting: setting(keyword_rules: [track_rule(enabled: false)]))
    assert_empty @sent
  end

  test 'keyword beats away, away beats welcome' do
    closed = WhatsappInboxSetting::DAYS.index_with { [] }
    s = setting(keyword_rules: [track_rule], away_enabled: true, welcome_enabled: true, business_hours: closed)

    Whatsapp::ShopTimezone.stub(:for, ActiveSupport::TimeZone['UTC']) do
      run_engine(message(body: 'track'), setting: s, created: true)
      run_engine(message(body: 'hi'), setting: s, created: true)
    end
    assert_equal ['Track here', 'We are away'], @sent.map { |k| k[:text] }
  end

  test 'welcome only goes to a brand new conversation' do
    s = setting(welcome_enabled: true)
    run_engine(message, setting: s, created: false)
    assert_empty @sent
    run_engine(message, setting: s, created: true)
    assert_equal ['Welcome!'], @sent.map { |k| k[:text] }
  end

  test 'no auto-reply when an agent replied in the last 6 hours' do
    s = setting(welcome_enabled: true)
    run_engine(message, setting: s, created: true, conversation: conversation(last_agent_reply_at: @now - 5.hours))
    assert_empty @sent

    run_engine(message, setting: s, created: true, conversation: conversation(last_agent_reply_at: @now - 7.hours))
    assert_equal 1, @sent.size
  end

  test 'at most one auto-reply per conversation per 6 hours' do
    s = setting(welcome_enabled: true)
    run_engine(message, setting: s, created: true, conversation: conversation(last_auto_reply_at: @now - 1.hour))
    assert_empty @sent

    run_engine(message, setting: s, created: true, claim: false)
    assert_empty @sent
  end

  test 'skips reactions, reserved COD payloads, stale messages and numbers that cannot send' do
    s = setting(welcome_enabled: true)
    run_engine(message(kind: 'reaction', body: nil), setting: s, created: true)
    run_engine(message(kind: 'button', body: 'Confirm', content: { 'payload' => 'cod_confirm' }), setting: s, created: true)
    run_engine(message(occurred_at: @now - 25.hours), setting: s, created: true)
    run_engine(message, setting: s, created: true, conversation: conversation(whatsapp_account: Account.new(false, nil)))
    run_engine(message, setting: s, created: true, conversation: conversation(open_window: false))
    assert_empty @sent
  end

  test 'a reply rejected before sending frees the 6 hour slot' do
    released = []
    failing = ->(**) { raise Whatsapp::Inbox::FreeformSender::NotReady }
    WhatsappConversation.stub(:find_by, conversation) do
      WhatsappConversationMessage.stub(:where, NoRows.new) do
        Engine.stub(:claim!, true) do
          Engine.stub(:release!, ->(*args) { released << args }) do
            Whatsapp::Inbox::FreeformSender.stub(:call, failing) do
              assert_nil Engine.call(message, conversation_created: true, setting: setting(welcome_enabled: true), now: @now)
            end
          end
        end
      end
    end
    assert_equal 1, released.size
  end
end
