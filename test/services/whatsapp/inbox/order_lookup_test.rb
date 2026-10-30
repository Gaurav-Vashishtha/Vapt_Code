# frozen_string_literal: true

require 'test_helper'

class Whatsapp::Inbox::OrderLookupTest < ActiveSupport::TestCase
  setup do
    @shop = shops(:regular_shop)
    @other = Shop.find(Shop.insert({ shopify_domain: 'lookup-other.myshopify.com', shopify_token: 'token',
                                     created_at: Time.current, updated_at: Time.current }, returning: :id).rows.first.first)
  end

  def order!(shop, number, attrs = {})
    OrderConfirmation.create!({ shop: shop, customer_number: number, status: 'COD-Verified', order_amount: '100',
                                currency: 'INR', is_cod_order: true }.merge(attrs))
  end

  test 'recent matches the last 10 digits whatever the stored format, newest first, shop scoped' do
    old = order!(@shop, '09876543210', created_at: 3.days.ago)
    new = order!(@shop, '+91 98765-43210', created_at: 1.day.ago)
    order!(@shop, '9876543210', status: 'Test-Order')
    order!(@other, '919876543210')

    assert_equal [new.id, old.id], Whatsapp::Inbox::OrderLookup.recent(@shop, '9876543210').map(&:id)
    assert_equal new.id, Whatsapp::Inbox::OrderLookup.latest(@shop, '919876543210')&.id
  end

  test 'recent keeps orders whose status is NULL' do
    oc = order!(@shop, '9876543210', status: nil)
    assert_includes Whatsapp::Inbox::OrderLookup.recent(@shop, '9876543210').map(&:id), oc.id
  end

  test 'short or blank phones match nothing' do
    order!(@shop, '1234')
    assert_empty Whatsapp::Inbox::OrderLookup.recent(@shop, '1234')
    assert_empty Whatsapp::Inbox::OrderLookup.recent(@shop, nil)
  end

  test 'lifetime sums free-text amounts without failing on junk' do
    order!(@shop, '9876543210', order_amount: 'Rs. 1,200.50', created_at: 2.days.ago)
    order!(@shop, '9876543210', order_amount: '300', currency: 'USD', created_at: 1.day.ago)
    order!(@shop, '9876543210', order_amount: 'n/a')
    totals = Whatsapp::Inbox::OrderLookup.lifetime(@shop, '9876543210')

    assert_equal 3, totals[:orders]
    assert_equal BigDecimal('1500.50'), totals[:value]
  end

  test 'lifetime of an unknown customer is zero' do
    totals = Whatsapp::Inbox::OrderLookup.lifetime(@shop, '5555555555')
    assert_equal 0, totals[:orders]
    assert_equal BigDecimal('0'), totals[:value]
    assert_nil totals[:currency]
  end

  test 'find_by_order_number accepts with or without hash and stays in the shop' do
    order!(@shop, '+91 98765 43210', order_number: '#1001')
    order!(@other, '911111111111', order_number: '#1001')

    assert_equal ['9876543210'], Whatsapp::Inbox::OrderLookup.find_by_order_number(@shop, '1001')
    assert_equal ['9876543210'], Whatsapp::Inbox::OrderLookup.find_by_order_number(@shop, '#1001')
    assert_empty Whatsapp::Inbox::OrderLookup.find_by_order_number(@shop, '')
  end

  test 'status_label maps COD statuses and appends shipping' do
    lookup = Whatsapp::Inbox::OrderLookup
    assert_equal 'Confirmed', lookup.status_label(OrderConfirmation.new(status: 'COD-Verified'))
    assert_equal 'Awaiting confirmation', lookup.status_label(OrderConfirmation.new(status: 'COD-Pending'))
    assert_equal 'Paid online', lookup.status_label(OrderConfirmation.new(status: 'COD-Prepaid'))
    assert_equal 'Cancelled · Delivered', lookup.status_label(OrderConfirmation.new(status: 'COD-Cancelled', shipping_status: 'delivered'))
    assert_equal '', lookup.status_label(nil)
  end
end
