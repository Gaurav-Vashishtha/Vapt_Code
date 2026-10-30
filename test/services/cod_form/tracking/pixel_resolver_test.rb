# frozen_string_literal: true

require_relative "../support/plain_boot"
require_relative "../../../../app/services/cod_form/tracking/pixel_resolver"

class CodFormPixelResolverTest < Minitest::Test
  PR = CodForm::Tracking::PixelResolver
  ALL_GATES = { "first_pixel" => { "allowed" => true }, "extra_pixels" => { "allowed" => true },
                "pixels_p3" => { "allowed" => true } }.freeze

  def row(id, platform, pixel_id, extra = {})
    { "id" => id, "platform" => platform, "pixel_id" => pixel_id, "access_token" => "tok#{id}",
      "config" => {}, "targeting" => {}, "position" => id }.merge(extra)
  end

  def keys(list)
    list.map { |p| "#{p['platform']}:#{p['pixel_id']}" }
  end

  def test_defaults_are_filled_in
    pixel = PR.select(pixels: [row(1, "meta", "111")], gates: ALL_GATES).first
    assert_equal true, pixel["config"]["browser"]
    assert_equal true, pixel["config"]["server"]
    assert_equal "purchase", pixel["config"]["purchase_event"]
    assert_equal({ "form_open" => true, "add_payment_info" => false, "purchase" => true }, pixel["config"]["events"])
    assert_equal "all", pixel["targeting"]["scope"]
  end

  def test_implicit_setting_pixel_comes_first_and_is_not_duplicated
    implicit = { "pixel_id" => "999", "access_token" => "settingtoken", "test_event_code" => "" }
    list = PR.select(pixels: [row(1, "meta", "111")], implicit_meta: implicit, gates: ALL_GATES)
    assert_equal %w[meta:999 meta:111], keys(list)
    assert list.first["implicit"]

    same = PR.select(pixels: [row(1, "meta", "999")], implicit_meta: implicit, gates: ALL_GATES)
    assert_equal %w[meta:999], keys(same)
    refute same.first["implicit"]
  end

  def test_implicit_pixel_without_token_is_browser_only
    list = PR.select(pixels: [], implicit_meta: { "pixel_id" => "999", "access_token" => "" }, gates: ALL_GATES)
    assert_equal false, list.first["config"]["server"]
    assert_equal true, list.first["config"]["browser"]
  end

  def test_meta_pixel_with_conversions_api_is_not_browser
    with_token = PR.select(pixels: [row(1, "meta", "a")], gates: ALL_GATES).first
    refute PR.browser?(with_token)

    no_token = PR.select(pixels: [row(2, "meta", "b", "access_token" => "")], gates: ALL_GATES).first
    assert PR.browser?(no_token)

    server_off = PR.select(pixels: [row(3, "meta", "c", "config" => { "server" => false })], gates: ALL_GATES).first
    assert PR.browser?(server_off)

    tiktok = PR.select(pixels: [row(4, "tiktok", "d")], gates: ALL_GATES).first
    assert PR.browser?(tiktok)
  end

  def test_extra_pixels_gate_keeps_only_the_first_per_platform
    gates = ALL_GATES.merge("extra_pixels" => { "allowed" => false })
    list = PR.select(pixels: [row(1, "meta", "a"), row(2, "meta", "b"), row(3, "tiktok", "c")], gates: gates)
    assert_equal %w[meta:a tiktok:c], keys(list)
  end

  def test_first_pixel_gate_and_unknown_gate_deny
    assert_empty PR.select(pixels: [row(1, "meta", "a")], gates: {})
    assert_empty PR.select(pixels: [row(1, "meta", "a")], gates: { "first_pixel" => { "allowed" => false } })
  end

  def test_p3_gate_covers_snapchat_pinterest_and_product_targeting
    gates = ALL_GATES.merge("pixels_p3" => { "allowed" => false })
    targeted = row(4, "meta", "t", "targeting" => { "scope" => "selected", "product_ids" => ["8111"] })
    list = PR.select(pixels: [row(1, "snapchat", "s"), row(2, "pinterest", "p"), row(3, "tiktok", "k"), targeted],
                     gates: gates, product_ids: ["8111"])
    assert_equal %w[tiktok:k], keys(list)
  end

  def test_limit_of_five_per_platform
    rows = (1..7).map { |i| row(i, "meta", "m#{i}") }
    assert_equal 5, PR.select(pixels: rows, gates: ALL_GATES).size
  end

  def test_product_targeting
    targeted = row(1, "meta", "t", "targeting" => { "scope" => "selected", "product_ids" => [8111], "collection_ids" => ["301"] })
    assert_equal 1, PR.select(pixels: [targeted], gates: ALL_GATES, product_ids: ["8111"]).size
    assert_equal 1, PR.select(pixels: [targeted], gates: ALL_GATES, collection_ids: [301]).size
    assert_empty PR.select(pixels: [targeted], gates: ALL_GATES, product_ids: ["1"])
    assert_empty PR.select(pixels: [targeted], gates: ALL_GATES)
  end

  def test_order_follows_position_then_id
    rows = [row(2, "tiktok", "b", "position" => 0), row(1, "tiktok", "a", "position" => 5)]
    assert_equal %w[tiktok:b tiktok:a], keys(PR.select(pixels: rows, gates: ALL_GATES))
  end

  def test_storefront_representation_drops_token_and_server_only_config
    pixel = PR.select(pixels: [row(1, "pinterest", "tag", "config" => { "ad_account_id" => "549", "test_event_code" => "X",
                                                                      "conversion_label" => "" })],
                      gates: ALL_GATES).first
    public_pixel = PR.storefront(pixel)
    assert_equal %w[config pixel_id platform targeting], public_pixel.keys.sort
    refute public_pixel["config"].key?("ad_account_id")
    refute public_pixel["config"].key?("test_event_code")
    refute public_pixel["config"].key?("server")
    assert public_pixel["config"].key?("purchase_event")
    refute_includes public_pixel.to_s, "tok1"
  end
end
