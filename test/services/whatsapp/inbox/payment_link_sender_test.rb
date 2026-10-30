# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class Whatsapp::Inbox::PaymentLinkSenderTest < ActiveSupport::TestCase
  Sender = Whatsapp::Inbox::PaymentLinkSender
  FakeSetting = Struct.new(:prepaid_notif, :locked)
  FakeShop = Struct.new(:setting)

  setup do
    @shop = shops(:regular_shop)
    @other = Shop.find(Shop.insert({ shopify_domain: 'paylink-other.myshopify.com', shopify_token: 'token',
                                     created_at: Time.current, updated_at: Time.current }, returning: :id).rows.first.first)
    account = WhatsappAccount.create!(shop: @shop, waba_id: 'waba-pl', phone_number_id: SecureRandom.hex(6), status: :verified)
    @conversation = WhatsappConversation.create!(shop: @shop, whatsapp_account: account, customer_wa_id: '919876543210',
                                                 phone_last10: '9876543210', status: :open, status_changed_at: Time.current,
                                                 last_inbound_at: Time.current, last_message_at: Time.current)
    @order = OrderConfirmation.create!(shop: @shop, customer_number: '+91 98765 43210', status: 'COD-Pending', is_cod_order: true)
    @cache = ActiveSupport::Cache::MemoryStore.new
  end

  def send_link(order = @order)
    Rails.stub(:cache, @cache) do
      Sender.stub(:shop_reason, nil) do
        yield if block_given?
        Sender.call(conversation: @conversation, order_confirmation: order, agent: nil)
      end
    end
  end

  test 'refuses orders from another shop or another customer' do
    foreign = OrderConfirmation.create!(shop: @other, customer_number: '919876543210', status: 'COD-Pending', is_cod_order: true)
    stranger = OrderConfirmation.create!(shop: @shop, customer_number: '919999999999', status: 'COD-Pending', is_cod_order: true)

    assert_equal :mismatch, send_link(foreign)
    assert_equal :mismatch, send_link(stranger)
    assert_equal :mismatch, send_link(nil)
  end

  test 'refuses prepaid or already confirmed orders' do
    @order.update!(is_cod_order: false)
    assert_equal :not_cod, send_link
    @order.update!(is_cod_order: true, status: 'COD-Verified')
    assert_equal :not_pending, send_link
  end

  test 'shop_reason covers disabled, paused and not eligible' do
    bsp = NetworkServices::WhatsappPrepaidBspService
    assert_equal :disabled, Sender.shop_reason(FakeShop.new(FakeSetting.new(false, false)))
    assert_equal :disabled, Sender.shop_reason(FakeShop.new(nil))
    bsp.stub(:paused?, true) do
      assert_equal :paused, Sender.shop_reason(FakeShop.new(FakeSetting.new(true, false)))
    end
    bsp.stub(:paused?, false) do
      bsp.stub(:eligible?, false) do
        assert_equal :not_eligible, Sender.shop_reason(FakeShop.new(FakeSetting.new(true, false)))
      end
      bsp.stub(:eligible?, true) do
        assert_nil Sender.shop_reason(FakeShop.new(FakeSetting.new(true, false)))
      end
    end
  end

  test 'sends once and rate limits the same order for 10 minutes' do
    Sender::WhatsappOnlyPrepaidMessage.stub(:call, WhatsappMessageLog.new) do
      assert_equal :sent, send_link
      assert_equal :rate_limited, send_link
    end
  end

  test 'a failed send reports send_failed and frees the rate limit' do
    Sender::WhatsappOnlyPrepaidMessage.stub(:call, nil) do
      assert_equal :send_failed, send_link
    end
    Sender::WhatsappOnlyPrepaidMessage.stub(:call, WhatsappMessageLog.new) do
      assert_equal :sent, send_link
    end
  end

  test 'never falls back to SMS or the shared number' do
    service = Sender::WhatsappOnlyPrepaidMessage.new(@shop, @order)
    assert_nil service.send(:send_without_bsp, nil)
  end
end
