# frozen_string_literal: true

require_relative "engine_test_helper"
require "digest"

class CodFormEngineAbTestTest < Minitest::Test
  A = CodForm::Engine::AbTest

  TEST = { "id" => 3, "variants" => [{ "key" => "a", "offer_id" => 12, "weight" => 50 }, { "key" => "control", "offer_id" => nil, "weight" => 50 }] }.freeze

  def test_assignment_follows_the_documented_hash
    %w[client-1 client-2 b0f6 zz].each do |seed|
      bucket = Digest::SHA256.hexdigest("3:#{seed}")[0, 8].to_i(16) % 100
      assert_equal bucket < 50 ? "a" : "control", A.assign(test: TEST, seed: seed)
    end
  end

  def test_is_deterministic_and_roughly_weighted
    assert_equal A.assign(test: TEST, seed: "same"), A.assign(test: TEST, seed: "same")
    counts = (1..2000).map { |i| A.assign(test: TEST, seed: "client-#{i}") }.tally
    assert_in_delta 1000, counts["a"], 150
    skewed = TEST.merge("variants" => [{ "key" => "a", "weight" => 100 }, { "key" => "b", "weight" => 0 }])
    assert_equal ["a"], (1..50).map { |i| A.assign(test: skewed, seed: i) }.uniq
  end

  def test_no_variants
    assert_nil A.assign(test: { "id" => 1, "variants" => [] }, seed: "x")
  end
end
