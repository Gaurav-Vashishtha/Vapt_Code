# frozen_string_literal: true

# Plain minitest, no Rails:  ruby test/services/cod_form/rate_limiter_test.rb
require "minitest/autorun"
require_relative "../../../app/services/cod_form/rate_limiter"

class CodFormRateLimiterTest < Minitest::Test
  R = CodForm::RateLimiter

  # The subset of ActiveSupport::Cache::Store the limiter uses.
  class FakeStore
    attr_reader :data, :expiries

    def initialize
      @data = Hash.new(0)
      @expiries = {}
    end

    def increment(key, amount = 1, expires_in: nil)
      @expiries[key] = expires_in
      @data[key] += amount
    end
  end

  class BrokenStore
    def increment(*)
      raise IOError, "redis down"
    end
  end

  def test_key_builders_match_the_architecture
    assert_equal "codf:otp:12:36301234567", R.otp_key(12, "36301234567")
    assert_equal "codf:order:12:36301234567", R.order_key(12, "36301234567")
  end

  def test_keys_are_scoped_per_shop_and_subject
    refute_equal R.otp_key(1, "36301234567"), R.otp_key(2, "36301234567")
    refute_equal R.otp_key(1, "36301234567"), R.otp_key(1, "36301234568")
    refute_equal R.otp_key(1, "36301234567"), R.order_key(1, "36301234567")
  end

  def test_subject_is_sanitised
    assert_equal "codf:otp:1:36301234567", R.otp_key(1, "+36 30 123:4567\n")
    assert_equal "a@b.co", R.normalize_subject(" A@B.co ")
    assert_equal 120, R.normalize_subject("9" * 500).length
  end

  def test_blank_subject_or_shop_gives_no_key
    assert_nil R.otp_key(1, "")
    assert_nil R.otp_key(1, nil)
    assert_nil R.order_key(nil, "36301234567")
  end

  def test_window_key_changes_per_period
    assert_equal "k:10", R.window_key("k", 60, Time.at(600))
    assert_equal "k:10", R.window_key("k", 60, Time.at(659))
    assert_equal "k:11", R.window_key("k", 60, Time.at(660))
  end

  def test_retry_after
    assert_equal 60, R.retry_after(60, now: Time.at(600))
    assert_equal 1, R.retry_after(60, now: Time.at(659))
    assert_equal 0, R.retry_after(0)
  end

  def test_hit_allows_up_to_the_limit_then_blocks
    store = FakeStore.new
    now = Time.at(1_000_000)
    results = 7.times.map { R.hit!("codf:otp:1:3630", limit: 5, period: 600, now: now, store: store) }
    assert_equal [true, true, true, true, true, false, false], results
    assert_equal [605], store.expiries.values.uniq
  end

  def test_a_new_window_resets_the_count
    store = FakeStore.new
    6.times { R.hit!("k", limit: 5, period: 600, now: Time.at(0), store: store) }
    refute R.hit!("k", limit: 5, period: 600, now: Time.at(599), store: store)
    assert R.hit!("k", limit: 5, period: 600, now: Time.at(600), store: store)
  end

  def test_different_keys_do_not_share_a_counter
    store = FakeStore.new
    5.times { R.hit!("a", limit: 5, period: 600, now: Time.at(0), store: store) }
    assert R.hit!("b", limit: 5, period: 600, now: Time.at(0), store: store)
  end

  def test_fails_open
    assert R.hit!("k", limit: 1, period: 60, store: BrokenStore.new)
    assert R.hit!(nil, limit: 1, period: 60, store: FakeStore.new)
    assert R.hit!("k", limit: 0, period: 60, store: FakeStore.new)
  end

  def test_default_limits
    assert_equal [5, 600], R.default_limit("otp_phone")
    assert_equal [5, 600], R.default_limit("order_phone")
  end
end
