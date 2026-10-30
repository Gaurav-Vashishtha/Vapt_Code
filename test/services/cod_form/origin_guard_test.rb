# frozen_string_literal: true

# Plain minitest, no Rails:  ruby test/services/cod_form/origin_guard_test.rb
require "minitest/autorun"
require_relative "../../../app/services/cod_form/origin_guard"

class CodFormOriginGuardTest < Minitest::Test
  G = CodForm::OriginGuard

  Shop = Struct.new(:id, :shopify_domain, :primary_domain)
  Config = Struct.new(:allowed_origins)
  Request = Struct.new(:headers)

  def setup
    @env = %w[COD_FORM_ORIGIN_ENFORCE COD_FORM_ALLOW_LOCALHOST COD_ORDERS_ORIGIN_ENFORCE].to_h { |k| [k, ENV[k]] }
    @env.each_key { |k| ENV.delete(k) }
    @shop = Shop.new(1, "brand.myshopify.com", "https://www.brand.hu")
    @config = Config.new(["brand.hu", "Shop.Brand.co"])
  end

  def teardown
    @env.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  def request(origin: nil, referer: nil)
    headers = {}
    headers["Origin"] = origin if origin
    headers["Referer"] = referer if referer
    Request.new(headers)
  end

  def test_extract_host
    assert_equal "brand.hu", G.extract_host("https://brand.hu")
    assert_equal "brand.hu", G.extract_host("https://BRAND.hu:8443/products/x?y=1")
    assert_equal "brand.hu", G.extract_host("brand.hu")
    assert_nil G.extract_host("")
    assert_nil G.extract_host(nil)
    assert_nil G.extract_host("null")
    assert_nil G.extract_host("https://exa mple.com")
  end

  def test_origin_wins_over_referer
    assert_equal "a.com", G.host_from("https://a.com", "https://b.com/page")
    assert_equal "b.com", G.host_from(nil, "https://b.com/page")
    assert_equal "b.com", G.host_from("null", "https://b.com/page")
    assert_nil G.host_from(nil, nil)
  end

  def test_allowed_hosts_are_normalised
    hosts = G.allowed_hosts(shopify_domain: "Brand.myshopify.com", primary_domain: "https://www.brand.hu/", extra: ["brand.hu", nil, "", "brand.hu"])
    assert_equal %w[brand.myshopify.com www.brand.hu brand.hu], hosts
  end

  def test_shop_domains_are_allowed
    %w[https://brand.myshopify.com https://www.brand.hu https://brand.hu https://shop.brand.co].each do |origin|
      assert G.allowed?(@shop, @config, request(origin: origin)), origin
    end
  end

  def test_referer_is_used_when_origin_is_missing
    assert G.allowed?(@shop, @config, request(referer: "https://www.brand.hu/products/widget"))
  end

  def test_other_hosts_are_rejected
    %w[https://evil.com https://brand.hu.evil.com https://evilbrand.hu https://other.myshopify.com
       https://www.brand.hu.attacker.io http://sub.www.brand.hu].each do |origin|
      refute G.allowed?(@shop, @config, request(origin: origin)), origin
    end
  end

  def test_missing_origin_and_referer_is_rejected
    refute G.allowed?(@shop, @config, request)
    assert_equal "missing_origin", G.check(@shop, @config, request)[:reason]
  end

  def test_shopify_preview_hosts
    assert G.allowed?(@shop, @config, request(origin: "https://abc123.shopifypreview.com"))
    refute G.allowed?(@shop, @config, request(origin: "https://shopifypreview.com"))
    refute G.allowed?(@shop, @config, request(origin: "https://evilshopifypreview.com"))
    refute G.allowed?(@shop, @config, request(origin: "https://abc.shopifypreview.com.evil.io"))
  end

  def test_localhost_only_with_the_switch
    refute G.allowed?(@shop, @config, request(origin: "http://localhost:3000"))
    ENV["COD_FORM_ALLOW_LOCALHOST"] = "true"
    assert G.allowed?(@shop, @config, request(origin: "http://localhost:3000"))
    assert G.allowed?(@shop, @config, request(origin: "http://127.0.0.1:8080"))
    refute G.allowed?(@shop, @config, request(origin: "http://localhost.evil.com"))
  end

  def test_enforcement_switch_turns_rejection_into_a_pass
    ENV["COD_FORM_ORIGIN_ENFORCE"] = "false"
    assert G.allowed?(@shop, @config, request(origin: "https://evil.com"))
    refute G.check(@shop, @config, request(origin: "https://evil.com"))[:allowed]
  end

  def test_works_without_a_shop_config
    assert G.allowed?(@shop, nil, request(origin: "https://www.brand.hu"))
    refute G.allowed?(@shop, nil, request(origin: "https://brand.hu"))
  end

  def test_rack_style_header_names
    assert G.allowed?(@shop, @config, Request.new({ "HTTP_ORIGIN" => "https://brand.hu" }))
  end

  def test_legacy_endpoint_is_log_only_by_default
    assert G.legacy_allowed?(@shop, request(origin: "https://evil.com"))
    ENV["COD_ORDERS_ORIGIN_ENFORCE"] = "true"
    refute G.legacy_allowed?(@shop, request(origin: "https://evil.com"))
    assert G.legacy_allowed?(@shop, request(origin: "https://brand.myshopify.com"))
  end
end
