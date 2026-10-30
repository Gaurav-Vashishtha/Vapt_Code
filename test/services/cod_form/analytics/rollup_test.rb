# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../../app/services/cod_form/analytics/rollup"

class CodFormAnalyticsRollupTest < Minitest::Test
  R = CodForm::Analytics::Rollup

  def ev(type, session, meta = {})
    { "type" => type, "session" => session,
      "meta" => { "country" => "HU", "device" => "mobile", "source" => "product", "form_id" => "5" }.merge(meta) }
  end

  def test_metric_keys_match_the_daily_stat_contract
    expected = %w[
      button_views form_opens first_inputs shipping_selected submit_attempts submit_errors orders
      revenue_cents partial_handoffs prepaid_redirects closes otp_sent otp_verified offer_views
      offer_accepts downsell_shown downsell_accepts upsell_views upsell_accepts recovery_opens
      recovered_orders blocked fallbacks
    ]
    assert_equal expected, R::METRIC_KEYS
    assert_equal R::DIMENSIONS, %w[all country device product form utm_campaign offer]
  end

  def test_every_stored_event_type_maps_to_a_metric
    stored = %w[
      cf_form_open cf_first_input cf_shipping_selected cf_submit_attempt cf_submit_error cf_order_created
      cf_form_close cf_prepaid_redirect cf_partial_handoff cf_prepaid_order cf_otp_sent cf_otp_verified
      cf_otp_bypassed cf_offer_view cf_offer_accept cf_downsell_shown cf_downsell_accept cf_upsell_view
      cf_upsell_accept cf_recovery_open cf_blocked cf_fallback
    ]
    assert_equal stored.sort, R::EVENT_METRICS.keys.sort
    R::EVENT_METRICS.each_value { |metric| assert_includes R::ALL_METRIC_KEYS, metric }
  end

  def test_basic_funnel_counts_and_revenue
    events = [
      ev("cf_form_open", "s1"), ev("cf_form_open", "s2"), ev("cf_form_open", "s3"),
      ev("cf_first_input", "s1"), ev("cf_first_input", "s2"),
      ev("cf_shipping_selected", "s1"),
      ev("cf_submit_attempt", "s1"),
      ev("cf_order_created", "s1", "value_cents" => 648_640, "currency" => "HUF"),
      ev("cf_form_close", "s2"), ev("cf_form_close", "s2")
    ]
    all = R.build(events: events)[["all", ""]]
    assert_equal 3, all["form_opens"]
    assert_equal 2, all["first_inputs"]
    assert_equal 1, all["shipping_selected"]
    assert_equal 1, all["submit_attempts"]
    assert_equal 1, all["orders"]
    assert_equal 648_640, all["revenue_cents"]
    assert_equal 2, all["closes"], "non-funnel metrics count events"
  end

  def test_funnel_steps_count_sessions_once
    events = [ev("cf_submit_attempt", "s1"), ev("cf_submit_attempt", "s1"), ev("cf_submit_attempt", "s1"),
              ev("cf_submit_error", "s1"), ev("cf_submit_error", "s1")]
    all = R.build(events: events)[["all", ""]]
    assert_equal 1, all["submit_attempts"]
    assert_equal 2, all["submit_errors"]
  end

  def test_test_sessions_are_excluded_from_every_aggregate
    events = [ev("cf_form_open", "s1", "test" => true), ev("cf_order_created", "s1", "test" => true, "value_cents" => 100)]
    assert_empty R.build(events: events)
  end

  def test_dimensions
    events = [
      ev("cf_form_open", "s1", "product_ids" => %w[8111 8222], "utm_campaign" => "autumn"),
      ev("cf_form_open", "s2", "country" => "CO", "device" => "desktop", "product_ids" => ["8111"]),
      ev("cf_order_created", "s2", "country" => "CO", "device" => "desktop", "product_ids" => ["8111"],
                                    "value_cents" => 5000)
    ]
    result = R.build(events: events)
    assert_equal 2, result[["all", ""]]["form_opens"]
    assert_equal 1, result[%w[country HU]]["form_opens"]
    assert_equal 1, result[%w[country CO]]["orders"]
    assert_equal 5000, result[%w[country CO]]["revenue_cents"]
    assert_equal 1, result[%w[device desktop]]["form_opens"]
    assert_equal 2, result[%w[product 8111]]["form_opens"]
    assert_equal 1, result[%w[product 8222]]["form_opens"]
    assert_equal 1, result[%w[form 5]]["orders"]
    assert_equal 1, result[%w[utm_campaign autumn]]["form_opens"]
    refute result.key?(%w[utm_campaign]), "no row for an empty value"
  end

  def test_offer_dimension
    events = [
      ev("cf_offer_view", "s1", "offer_id" => 21), ev("cf_offer_view", "s2", "offer_id" => 21),
      ev("cf_offer_accept", "s1", "offer_id" => 21),
      ev("cf_downsell_shown", "s1", "offer_id" => "30"), ev("cf_downsell_accept", "s1", "offer_id" => "30"),
      ev("cf_upsell_view", "s1", "offer_id" => 33), ev("cf_upsell_accept", "s1", "offer_id" => 33)
    ]
    result = R.build(events: events)
    assert_equal 2, result[%w[offer 21]]["offer_views"]
    assert_equal 1, result[%w[offer 21]]["offer_accepts"]
    assert_equal 1, result[%w[offer 30]]["downsell_accepts"]
    assert_equal 1, result[%w[offer 33]]["upsell_accepts"]
    assert_equal 1, result[["all", ""]]["downsell_shown"]
  end

  def test_otp_recovery_and_other_counters
    events = [
      ev("cf_otp_sent", "s1"), ev("cf_otp_sent", "s1"), ev("cf_otp_verified", "s1"), ev("cf_otp_bypassed", "s2"),
      ev("cf_recovery_open", "s3", "source" => "recovery"),
      ev("cf_order_created", "s3", "source" => "recovery", "value_cents" => 1000),
      ev("cf_order_created", "s4", "recovered" => true, "value_cents" => 1000),
      ev("cf_blocked", "s5"), ev("cf_fallback", "c1", "reason" => "bundle"),
      ev("cf_partial_handoff", "s6"), ev("cf_prepaid_redirect", "s7"), ev("cf_prepaid_order", "s7")
    ]
    all = R.build(events: events)[["all", ""]]
    assert_equal 2, all["otp_sent"]
    assert_equal 1, all["otp_verified"]
    assert_equal 1, all["otp_bypassed"]
    assert_equal 1, all["recovery_opens"]
    assert_equal 2, all["recovered_orders"]
    assert_equal 2, all["orders"]
    assert_equal 1, all["blocked"]
    assert_equal 1, all["fallbacks"]
    assert_equal 1, all["partial_handoffs"]
    assert_equal 1, all["prepaid_redirects"]
    assert_equal 1, all["prepaid_orders"]
  end

  def test_button_views_fold_into_all_country_device_product
    result = R.build(events: [], button_views: { "HU|mobile|8111" => 10, "HU|desktop|8111" => "5", "CO|mobile|" => 2,
                                                 "||" => 1, "HU|mobile|9" => 0 })
    assert_equal 18, result[["all", ""]]["button_views"]
    assert_equal 15, result[%w[country HU]]["button_views"]
    assert_equal 12, result[%w[device mobile]]["button_views"]
    assert_equal 15, result[%w[product 8111]]["button_views"]
    refute result.key?(%w[product 9])
  end

  def test_revenue_is_converted_to_shop_currency
    convert = ->(cents, currency) { currency == "EUR" ? cents * 400 : cents }
    events = [ev("cf_order_created", "s1", "value_cents" => 1000, "currency" => "EUR"),
              ev("cf_order_created", "s2", "value_cents" => 648_640, "currency" => "HUF")]
    assert_equal 400_000 + 648_640, R.build(events: events, convert: convert)[["all", ""]]["revenue_cents"]
  end

  def test_revenue_kept_when_converter_has_no_rate
    events = [ev("cf_order_created", "s1", "value_cents" => 1000, "currency" => "XXX")]
    assert_equal 1000, R.build(events: events, convert: ->(_c, _cur) {})[["all", ""]]["revenue_cents"]
  end

  def test_unknown_types_and_garbage_are_ignored
    result = R.build(events: [nil, "x", { "type" => "cf_button_view", "session" => "s" }, { "type" => "form_view" },
                              { "type" => "cf_client_error", "meta" => {} }])
    assert_empty result
  end

  def test_sum_adds_metric_hashes
    total = R.sum([{ "orders" => 2, "revenue_cents" => 500 }, { "orders" => 1, "form_opens" => 9 }, nil,
                   { "orders" => "bad" }])
    assert_equal 3, total["orders"]
    assert_equal 500, total["revenue_cents"]
    assert_equal 9, total["form_opens"]
    assert_equal 0, total["closes"]
  end

  def test_cap_cardinality_keeps_the_biggest_values_and_all
    result = { ["all", ""] => { "form_opens" => 100 } }
    10.times { |i| result[["product", "p#{i}"]] = { "form_opens" => i, "orders" => 0 } }
    result[%w[product star]] = { "form_opens" => 0, "orders" => 1 }
    capped = R.cap_cardinality(result, limit: 3)
    assert capped.key?(["all", ""])
    assert_equal %w[p8 p9 star], capped.keys.select { |d, _| d == "product" }.map(&:last).sort
  end

  def test_long_dimension_values_are_truncated
    result = R.build(events: [ev("cf_form_open", "s1", "utm_campaign" => "x" * 500)])
    key = result.keys.find { |dimension, _| dimension == "utm_campaign" }
    assert_equal 120, key.last.length
  end
end
