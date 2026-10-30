# frozen_string_literal: true

require "test_helper"

class CodForm::SessionTest < ActiveSupport::TestCase
  setup do
    @shop = shops(:regular_shop)
  end

  test "a new session gets a uuid, open status and a two-hour expiry" do
    session = CodForm::Session.create!(shop: @shop)

    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/, session.public_id)
    assert_equal "open", session.status
    assert_equal "product", session.source
    assert_in_delta 2.hours.from_now.to_f, session.expires_at.to_f, 5
    assert_not session.expired?
    assert session.expired?(3.hours.from_now)
  end

  test "mark_ordered! stores the order and extra columns" do
    session = CodForm::Session.create!(shop: @shop, quote_snapshot: { "total_cents" => 1_649_000 })
    order = Struct.new(:id, :name).new(5_551_234, "#1042")

    session.mark_ordered!(order, phone_normalized: "36301234567")

    session.reload
    assert_equal "ordered", session.status
    assert_equal "5551234", session.order_id
    assert_equal "#1042", session.order_name
    assert_equal 1_649_000, session.order_total_cents
    assert_equal "36301234567", session.phone_normalized
    assert_not_nil session.ordered_at
    assert session.ordered?
  end

  test "mark_ordered! accepts a hash" do
    session = CodForm::Session.create!(shop: @shop)
    session.mark_ordered!({ "id" => "77", "name" => "#7", "total_cents" => 500 })

    assert_equal %w[77 #7], [session.order_id, session.order_name]
    assert_equal 500, session.order_total_cents
  end

  test "inspect hides buyer data" do
    session = CodForm::Session.create!(shop: @shop, ip: "203.0.113.9",
                                       contact: { "phone_e164" => "+36301234567" },
                                       address: { "address1" => "Fo utca 1" })

    assert_not_includes session.inspect, "203.0.113.9"
    assert_not_includes session.inspect, "36301234567"
    assert_not_includes session.inspect, "Fo utca"
  end

  test "rejects unknown status and source" do
    assert_not CodForm::Session.new(shop: @shop, status: "done").valid?
    assert_not CodForm::Session.new(shop: @shop, source: "popup").valid?
  end
end
