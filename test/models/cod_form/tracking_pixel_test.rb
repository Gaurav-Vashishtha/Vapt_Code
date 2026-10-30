# frozen_string_literal: true

require "test_helper"

class CodForm::TrackingPixelTest < ActiveSupport::TestCase
  setup do
    @shop = shops(:regular_shop)
  end

  test "the access token is masked and never serialised or inspected" do
    pixel = CodForm::TrackingPixel.create!(shop: @shop, platform: "tiktok", pixel_id: "C4ABCDEF123",
                                           access_token: "secret-token-9f2a")

    assert_equal "••••9f2a", pixel.access_token_masked
    assert_not pixel.as_json.key?("access_token")
    assert_not_includes pixel.to_json, "secret-token"
    assert_not_includes pixel.inspect, "secret-token"
  end

  test "pixel id is unique per shop and platform; at most five per platform" do
    5.times { |i| CodForm::TrackingPixel.create!(shop: @shop, platform: "meta", pixel_id: "10#{i}") }

    assert CodForm::TrackingPixel.new(shop: @shop, platform: "meta", pixel_id: "999").invalid?
    assert CodForm::TrackingPixel.new(shop: @shop, platform: "tiktok", pixel_id: "100").valid?
    assert CodForm::TrackingPixel.new(shop: @shop, platform: "bing", pixel_id: "1").invalid?
  end
end
