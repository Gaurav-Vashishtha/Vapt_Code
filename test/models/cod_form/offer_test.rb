# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class CodForm::OfferTest < ActiveSupport::TestCase
  setup do
    @shop = shops(:regular_shop)
  end

  def build_offer(attrs = {})
    CodForm::Offer.new({ shop: @shop, offer_type: "bump", name: "Bump" }.merge(attrs))
  end

  test "defaults to draft and validates type and status" do
    offer = build_offer
    assert offer.valid?
    assert_equal "draft", offer.status

    assert_not build_offer(offer_type: "bundle").valid?
    assert_not build_offer(status: "live").valid?
  end

  test "active_now respects status and schedule" do
    live = build_offer(status: "active").tap(&:save!)
    build_offer(status: "paused").save!
    build_offer(status: "active", starts_at: 1.day.from_now).save!
    build_offer(status: "active", starts_at: 2.days.ago, ends_at: 1.day.ago).save!

    assert_equal [live.id], CodForm::Offer.where(shop_id: @shop.id).active_now.pluck(:id)
    assert live.active_now?
  end

  test "only one active downsell per shop" do
    build_offer(offer_type: "downsell", name: "First", status: "active").save!
    second = build_offer(offer_type: "downsell", name: "Second", status: "active")

    assert_not second.valid?
    second.status = "draft"
    assert second.valid?
  end

  test "an active quantity offer is rejected when the engine reports an overlap" do
    offer = build_offer(offer_type: "quantity", name: "Qty", status: "active",
                        targeting: { "scope" => "selected", "product_ids" => ["8111"], "collection_ids" => [] })

    CodForm::Engine::OfferOverlap.stub(:conflicts, [{ "product_id" => "8111", "offer_ids" => [1, nil] }]) do
      assert_not offer.valid?
      assert offer.errors[:targeting].any?
    end

    CodForm::Engine::OfferOverlap.stub(:conflicts, []) do
      assert offer.valid?
    end
  end
end
