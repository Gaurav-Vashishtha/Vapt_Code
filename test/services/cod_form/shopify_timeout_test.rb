# Plain minitest, no Rails: ruby test/services/cod_form/shopify_timeout_test.rb
require "minitest/autorun"
require_relative "../../../lib/cod_form_shopify_timeout"

# F.2 "Shopify HTTP read timeout 12 s" — lib/cod_form_shopify_timeout.rb.
class CodFormShopifyTimeoutTest < Minitest::Test
  # Stand-in for GraphQL::Client::HTTP (ShopifyAPI::GraphQL::HTTPClient's superclass).
  class FakeHttpAdapter
    def connection
      Net::HTTP.new("example.myshopify.com", 443)
    end
  end

  def setup
    CodFormShopifyTimeout.install!(FakeHttpAdapter)
  end

  def test_no_timeout_outside_a_block_so_other_services_keep_the_defaults
    assert_nil CodFormShopifyTimeout.current
    http = FakeHttpAdapter.new.connection
    assert_equal Net::HTTP.new("x", 443).read_timeout, http.read_timeout
    assert_equal Net::HTTP.new("x", 443).open_timeout, http.open_timeout
  end

  def test_twelve_seconds_inside_a_block
    CodFormShopifyTimeout.with do
      http = FakeHttpAdapter.new.connection
      assert_equal 12, http.read_timeout
      assert_equal 5, http.open_timeout
    end
    assert_nil CodFormShopifyTimeout.current
  end

  def test_nesting_restores_the_outer_value_and_survives_exceptions
    CodFormShopifyTimeout.with(12) do
      CodFormShopifyTimeout.with(3) { assert_equal 3, FakeHttpAdapter.new.connection.read_timeout }
      assert_equal 12, CodFormShopifyTimeout.current
      assert_raises(RuntimeError) { CodFormShopifyTimeout.with(4) { raise "boom" } }
      assert_equal 12, CodFormShopifyTimeout.current
    end
    assert_nil CodFormShopifyTimeout.current
  end

  def test_thread_local
    seen = nil
    CodFormShopifyTimeout.with { Thread.new { seen = CodFormShopifyTimeout.current }.join }
    assert_nil seen
  end

  def test_install_is_idempotent_and_refuses_classes_without_a_connection
    assert CodFormShopifyTimeout.install!(FakeHttpAdapter)
    assert_equal 1, FakeHttpAdapter.ancestors.count(CodFormShopifyTimeout::Connection)
    refute CodFormShopifyTimeout.install!(Class.new)
    refute CodFormShopifyTimeout.install!(nil)
  end
end
