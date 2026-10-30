# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class Whatsapp::Inbox::ReplyVariablesTest < ActiveSupport::TestCase
  Conversation = Struct.new(:shop, :phone_last10, :customer_name, :whatsapp_account, keyword_init: true)
  Account = Struct.new(:verified_name)
  Order = Struct.new(:order_number, :order_status_url, :order_amount, :currency, :customer_name, keyword_init: true)
  Shop = Struct.new(:id, :shopify_domain)

  def conversation(name: 'Aman Gupta', verified_name: 'Glow Store')
    Conversation.new(shop: Shop.new(1, 'glow-store.myshopify.com'), phone_last10: '9876543210',
                     customer_name: name, whatsapp_account: Account.new(verified_name))
  end

  def order
    Order.new(order_number: '1042', order_status_url: 'https://glow.in/s/1042', order_amount: '1299.00',
              currency: 'INR', customer_name: 'Aman G')
  end

  def with_order(value)
    Whatsapp::Inbox::OrderLookup.stub(:latest, value) do
      Whatsapp::Inbox::OrderLookup.stub(:status_label, 'Confirmed') { yield }
    end
  end

  test 'fills every variable from the latest order' do
    with_order(order) do
      values = Whatsapp::Inbox::ReplyVariables.values_for(conversation)
      assert_equal 'Aman Gupta', values['name']
      assert_equal 'Aman', values['first_name']
      assert_equal '#1042', values['order_number']
      assert_equal 'Confirmed', values['order_status']
      assert_equal 'https://glow.in/s/1042', values['tracking_url']
      assert_equal 'INR 1299.00', values['order_amount']
      assert_equal 'Glow Store', values['store_name']
    end
  end

  test 'blank and unknown variables render empty without stray spaces' do
    with_order(nil) do
      text = Whatsapp::Inbox::ReplyVariables.render(conversation(name: nil, verified_name: nil),
                                                    'Hi {{first_name}}, your order {{order_number}} {{foo}} is here. {{store_name}}')
      assert_equal 'Hi, your order is here. Glow Store', text
    end
  end

  test 'text without variables skips the order lookup' do
    Whatsapp::Inbox::OrderLookup.stub(:latest, ->(*) { raise 'should not be called' }) do
      assert_equal 'Thanks!', Whatsapp::Inbox::ReplyVariables.render(conversation, '  Thanks! ')
    end
  end
end
