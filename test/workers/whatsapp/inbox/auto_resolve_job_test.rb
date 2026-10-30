# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class Whatsapp::Inbox::AutoResolveJobTest < ActiveSupport::TestCase
  setup do
    @shop = shops(:regular_shop)
    @now = Time.current
  end

  def create_conversation(wa_id, status:, status_changed_at:, last_inbound_at:)
    WhatsappConversation.create!(
      shop_id: @shop.id, customer_wa_id: wa_id, phone_last10: wa_id.last(10), status: status,
      status_changed_at: status_changed_at, last_inbound_at: last_inbound_at, last_message_at: status_changed_at
    )
  end

  test 'resolves only pending conversations silent for 72 hours since the agent reply' do
    stale = create_conversation('919800000001', status: :pending, status_changed_at: @now - 73.hours,
                                                last_inbound_at: @now - 74.hours)
    recent = create_conversation('919800000002', status: :pending, status_changed_at: @now - 10.hours,
                                                 last_inbound_at: @now - 11.hours)
    open_one = create_conversation('919800000003', status: :open, status_changed_at: @now - 80.hours,
                                                   last_inbound_at: @now - 80.hours)
    replied_after = create_conversation('919800000004', status: :pending, status_changed_at: @now - 80.hours,
                                                        last_inbound_at: @now - 1.hour)

    resolved = []
    Whatsapp::Inbox::ConversationState.stub(:resolve!, ->(conv, by:) { resolved << [conv.id, by] }) do
      Whatsapp::Inbox::AutoResolveJob.new.perform
    end

    assert_equal [[stale.id, 'auto']], resolved
    assert_not_includes resolved.map(&:first), recent.id
    assert_not_includes resolved.map(&:first), open_one.id
    assert_not_includes resolved.map(&:first), replied_after.id
  end
end
