require 'test_helper'
require 'minitest/mock'

class CustomerSyncStateTest < ActiveSupport::TestCase
  def build_shop(index, pulled: false)
    Shop.create!(
      shopify_domain: "sync-test-#{index}-#{SecureRandom.hex(3)}.myshopify.com",
      shopify_token: 'token',
      country_code: 'IN',
      initial_customer_pull_completed: pulled ? 1.day.ago : nil
    )
  end

  def build_state(shop, shopify:, baseline:, **attrs)
    CustomerSyncState.create!({ shop_id: shop.id, shopify_customer_count: shopify, baseline_count: baseline, count_synced_at: Time.current }.merge(attrs))
  end

  test 'plannable returns the shop with the most unloaded customers first' do
    first = build_state(build_shop(1), shopify: 110, baseline: 100)
    second = build_state(build_shop(2), shopify: 120, baseline: 100)
    third = build_state(build_shop(3), shopify: 30, baseline: 0)
    build_state(build_shop(4), shopify: 50, baseline: 50)

    picked = CustomerSyncState.where(id: [first, second, third].map(&:id)).plannable(10)

    assert_equal [third.id, second.id, first.id], picked.map(&:id)
  end

  test 'plannable skips shops in backoff and shops with an active export' do
    backing_off = build_state(build_shop(5), shopify: 500, baseline: 0, status: 'backoff', next_attempt_at: 1.hour.from_now)
    exporting_shop = build_shop(6)
    exporting = build_state(exporting_shop, shopify: 400, baseline: 0)
    CustomerBulkExport.create!(shop: exporting_shop, shopify_domain: exporting_shop.shopify_domain, status: 'running', requested_at: Time.current)
    ready = build_state(build_shop(7), shopify: 10, baseline: 0)

    picked = CustomerSyncState.where(id: [backing_off, exporting, ready].map(&:id)).plannable(10)

    assert_equal [ready.id], picked.map(&:id)
  end

  test 'only one big shop is planned while the big lane is full' do
    big_a = build_state(build_shop(8), shopify: 300_000, baseline: 0)
    big_b = build_state(build_shop(9), shopify: 250_000, baseline: 0)
    small = build_state(build_shop(10), shopify: 40, baseline: 0)

    picked = CustomerSyncState.where(id: [big_a, big_b, small].map(&:id)).plannable(10)

    assert_equal [big_a.id, small.id], picked.map(&:id)
  end

  test 'record_count! counts customers created since the last pull as unloaded for an already pulled shop' do
    shop = build_shop(11, pulled: true)

    state = ShopifyServices::CustomerCountFetchService.stub(:call, 5) { CustomerSyncState.record_count!(shop, 80) }

    assert_equal 75, state.baseline_count
    assert_equal 5, state.reload.unloaded_count
  end

  test 'record_count! does not create a state when the created-since lookup fails' do
    shop = build_shop(18, pulled: true)

    result = ShopifyServices::CustomerCountFetchService.stub(:call, nil) { CustomerSyncState.record_count!(shop, 80) }

    assert_nil result
    assert_nil CustomerSyncState.find_by(shop_id: shop.id)
  end

  test 'record_count! never makes the baseline negative' do
    shop = build_shop(19, pulled: true)

    state = ShopifyServices::CustomerCountFetchService.stub(:call, 500) { CustomerSyncState.record_count!(shop, 80) }

    assert_equal 0, state.baseline_count
    assert_equal 80, state.reload.unloaded_count
  end

  test 'reseed! corrects a baseline that assumed everything was loaded' do
    shop = build_shop(20, pulled: true)
    state = build_state(shop, shopify: 100, baseline: 100)

    ShopifyServices::CustomerCountFetchService.stub(:call, 12) { assert CustomerSyncState.reseed!(state) }

    assert_equal 88, state.reload.baseline_count
    assert_equal 12, state.unloaded_count
  end

  test 'record_count! leaves a never pulled shop fully unloaded' do
    shop = build_shop(12)

    state = CustomerSyncState.record_count!(shop, 80)

    assert_equal 0, state.baseline_count
    assert_equal 80, state.reload.unloaded_count
  end

  test 'record_count! lowers the baseline when customers were deleted' do
    shop = build_shop(13)
    build_state(shop, shopify: 100, baseline: 100)

    state = CustomerSyncState.record_count!(shop, 70)

    assert_equal 70, state.baseline_count
    assert_equal 0, state.reload.unloaded_count
  end

  test 'record_count! re-enables a disabled shop' do
    shop = build_shop(14)
    build_state(shop, shopify: 5, baseline: 0, status: 'disabled', consecutive_failures: 4)

    state = CustomerSyncState.record_count!(shop, 9)

    assert_equal 'idle', state.status
    assert_equal 0, state.consecutive_failures
  end

  test 'record_failure! backs off and flags the shop after repeated failures' do
    shop = build_shop(15)
    state = build_state(shop, shopify: 10, baseline: 0)

    CustomerSyncState.record_failure!(shop.id, 'boom')
    state.reload
    assert_equal 'backoff', state.status
    assert_equal 1, state.consecutive_failures
    assert_operator state.next_attempt_at, :>, 4.minutes.from_now

    7.times { CustomerSyncState.record_failure!(shop.id, 'boom') }
    assert_equal 'needs_attention', state.reload.status
  end

  test 'record_failure! without counting keeps the failure count' do
    shop = build_shop(16)
    state = build_state(shop, shopify: 10, baseline: 0)

    CustomerSyncState.record_failure!(shop.id, 'shop busy', count_failure: false)

    assert_equal 0, state.reload.consecutive_failures
    assert_equal 'backoff', state.status
  end

  test 'record_success! moves the baseline to the exported count' do
    shop = build_shop(17)
    state = build_state(shop, shopify: 130, baseline: 100)

    CustomerSyncState.record_success!(shop.id, baseline: 120)

    state.reload
    assert_equal 120, state.baseline_count
    assert_equal 10, state.unloaded_count
    assert_equal 'idle', state.status
  end

  test 'unauthorized_message? recognises a revoked token' do
    assert CustomerSyncState.unauthorized_message?('Shopify GraphQL errors: [{"message":"401 Unauthorized"}]')
    assert CustomerSyncState.unauthorized_message?('Unauthorized')
    assert_not CustomerSyncState.unauthorized_message?('execution expired')
  end

  test 'mark_unreachable! disables the shop without counting it as loaded or pending' do
    shop = build_shop(21)

    CustomerSyncState.mark_unreachable!(shop, '401 Unauthorized')

    state = CustomerSyncState.find_by!(shop_id: shop.id)
    assert_equal 'disabled', state.status
    assert_equal 0, state.shopify_customer_count
    assert_empty CustomerSyncState.where(id: state.id).plannable(5)
  end

  test 'a shop that was unreachable is re-enabled and re-seeded when its count is recorded again' do
    shop = build_shop(22, pulled: true)
    CustomerSyncState.mark_unreachable!(shop, '401 Unauthorized')

    state = ShopifyServices::CustomerCountFetchService.stub(:call, 3) { CustomerSyncState.record_count!(shop, 50) }

    assert_equal 'idle', state.status
    assert_equal 47, state.baseline_count
    assert_equal 3, state.reload.unloaded_count
  end

  test 'schedule_recheck enqueues a count only for shops disabled because of a 401' do
    unreachable = build_shop(23)
    CustomerSyncState.mark_unreachable!(unreachable, 'token no longer valid')
    out_of_scope = build_shop(24)
    build_state(out_of_scope, shopify: 5, baseline: 0, status: 'disabled', last_error: 'no longer an active install')
    untracked = build_shop(25)
    calls = []

    ShopifyJobs::CustomerCountShopJob.stub(:perform_in, ->(*args) { calls << args }) do
      CustomerSyncState.schedule_recheck(unreachable.id)
      CustomerSyncState.schedule_recheck(out_of_scope.id)
      CustomerSyncState.schedule_recheck(untracked.id)
    end

    assert_equal 1, calls.size
    assert_equal unreachable.id, calls.first.last
  end
end
