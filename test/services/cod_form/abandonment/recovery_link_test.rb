# frozen_string_literal: true

require_relative "../support/plain_boot"
require_relative "../../../../app/services/cod_form/abandonment/recovery_link"

class CodFormRecoveryLinkTest < Minitest::Test
  RL = CodForm::Abandonment::RecoveryLink

  def test_default_link_is_the_home_page
    assert_equal "https://brand.hu/?codk_recover=tok123", RL.build(primary_domain: "brand.hu", token: "tok123")
    assert_equal "https://brand.hu/?codk_recover=tok123", RL.build(primary_domain: "https://Brand.hu/", token: "tok123", source: "cart")
  end

  def test_product_session_reopens_on_its_product_page
    url = RL.build(primary_domain: "brand.hu", token: "tok", source: "product",
                   page_url: "https://brand.hu/products/widget?utm_source=fb&codk_recover=old#reviews")
    assert_equal "https://brand.hu/products/widget?utm_source=fb&codk_recover=tok", url
    plain = RL.build(primary_domain: "brand.hu", token: "tok", source: "product", page_url: "https://brand.hu/products/widget")
    assert_equal "https://brand.hu/products/widget?codk_recover=tok", plain
  end

  def test_page_on_another_allowed_host
    url = RL.build(primary_domain: "brand.hu", token: "tok", source: "product",
                   page_url: "https://shop.myshopify.com/products/w", allowed_hosts: ["shop.myshopify.com"])
    assert_equal "https://shop.myshopify.com/products/w?codk_recover=tok", url
  end

  def test_foreign_or_unsafe_page_url_falls_back_to_the_shop_home
    home = "https://brand.hu/?codk_recover=tok"
    ["https://evil.example/products/widget", "http://brand.hu/products/widget", "javascript:alert(1)", "not a url", nil,
     "https://brand.hu.evil.example/p"].each do |page|
      assert_equal home, RL.build(primary_domain: "brand.hu", token: "tok", source: "product", page_url: page), page.inspect
    end
  end

  def test_no_link_without_domain_or_token
    assert_nil RL.build(primary_domain: "", token: "tok")
    assert_nil RL.build(primary_domain: "brand.hu", token: "")
    assert_nil RL.build(primary_domain: "localhost", token: "tok")
  end

  def test_token_is_escaped
    assert_equal "https://brand.hu/?codk_recover=a%2Fb", RL.build(primary_domain: "brand.hu", token: "a/b")
  end

  def test_host_of
    assert_equal "brand.hu", RL.host_of("https://brand.hu/path?x=1")
    assert_equal "www.brand.com", RL.host_of("WWW.Brand.com")
    assert_nil RL.host_of("bad host.com")
    assert_nil RL.host_of(nil)
  end
end
