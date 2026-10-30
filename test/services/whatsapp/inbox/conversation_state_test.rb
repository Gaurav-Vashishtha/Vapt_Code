# frozen_string_literal: true

require 'test_helper'

class Whatsapp::Inbox::ConversationStateTest < ActiveSupport::TestCase
  State = Whatsapp::Inbox::ConversationState

  setup do
    @shop = shops(:regular_shop)
    @account = WhatsappAccount.create!(shop: @shop, waba_id: 'waba-state', phone_number_id: SecureRandom.hex(6), status: :verified)
    @agent = WhatsappInboxAgent.create!(shop: @shop, shopify_user_id: 7, name: 'Riya')
    now = Time.current
    @conversation = WhatsappConversation.create!(shop: @shop, whatsapp_account: @account, customer_wa_id: '919822222222',
                                                 phone_last10: '9822222222', status: :open, status_changed_at: now,
                                                 last_inbound_at: now, last_message_at: now)
  end

  test 'inbound on a new conversation opens the first episode' do
    State.on_inbound!(@conversation, at: Time.current)
    assert @conversation.reload.current_episode
    assert_nil @conversation.current_episode.resolved_at
  end

  test 'agent reply records first response once and moves to pending' do
    State.on_inbound!(@conversation, at: 5.minutes.ago)
    first_at = 2.minutes.ago
    State.on_agent_reply!(@conversation, agent: @agent, at: first_at)
    State.on_agent_reply!(@conversation, agent: nil, at: Time.current)

    @conversation.reload
    assert @conversation.pending?
    assert_equal first_at.to_i, @conversation.current_episode.first_response_at.to_i
    assert_equal @agent.id, @conversation.current_episode.first_response_agent_id
  end

  test 'send and resolve closes the episode' do
    State.on_inbound!(@conversation, at: 5.minutes.ago)
    State.on_agent_reply!(@conversation, agent: @agent, at: Time.current, resolve: true)
    @conversation.reload
    assert @conversation.resolved?
    assert_equal 'agent', @conversation.current_episode.resolved_by
  end

  test 'customer message after pending reopens the same episode' do
    State.on_inbound!(@conversation, at: 10.minutes.ago)
    episode_id = @conversation.reload.current_episode_id
    State.on_agent_reply!(@conversation, agent: @agent, at: 5.minutes.ago)
    State.on_inbound!(@conversation, at: Time.current)
    @conversation.reload
    assert @conversation.open?
    assert_equal episode_id, @conversation.current_episode_id
  end

  test 'manual reopen from resolved starts a new episode; auto resolve records who' do
    State.on_inbound!(@conversation, at: 10.minutes.ago)
    State.resolve!(@conversation)
    assert_equal 'auto', @conversation.reload.current_episode.resolved_by
    first = @conversation.current_episode_id

    State.set_status!(@conversation, 'open', agent: @agent)
    refute_equal first, @conversation.reload.current_episode_id
    assert_raises(ArgumentError) { State.set_status!(@conversation, 'closed') }
  end

  test 'setting the same status is a no-op' do
    changed_at = @conversation.status_changed_at
    State.set_status!(@conversation, 'open')
    assert_equal changed_at.to_i, @conversation.reload.status_changed_at.to_i
  end
end
