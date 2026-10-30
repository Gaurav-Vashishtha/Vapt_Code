# frozen_string_literal: true

require "minitest/autorun"
require "date"
require_relative "../../../../app/services/cod_form/analytics/funnel"

class CodFormAnalyticsFunnelTest < Minitest::Test
  F = CodForm::Analytics::Funnel

  METRICS = {
    "button_views" => 1000, "form_opens" => 200, "first_inputs" => 150, "shipping_selected" => 90,
    "submit_attempts" => 60, "orders" => 40, "revenue_cents" => 1_000_000, "prepaid_redirects" => 7,
    "partial_handoffs" => 3, "otp_sent" => 50, "otp_verified" => 45, "otp_bypassed" => 2,
    "recovery_opens" => 10, "recovered_orders" => 4, "offer_views" => 80, "offer_accepts" => 20
  }.freeze

  def test_steps_in_contract_order
    assert_equal(
      [{ "step" => "button_views", "count" => 1000 }, { "step" => "form_opens", "count" => 200 },
       { "step" => "first_inputs", "count" => 150 }, { "step" => "shipping_selected", "count" => 90 },
       { "step" => "submit_attempts", "count" => 60 }, { "step" => "orders", "count" => 40 }],
      F.steps(METRICS)
    )
    assert_equal 0, F.steps({}).sum { |s| s["count"] }
  end

  def test_totals
    assert_equal(
      { "orders" => 40, "revenue_cents" => 1_000_000, "aov_cents" => 25_000, "conversion_rate" => 20.0,
        "prepaid_redirects" => 7, "partial_handoffs" => 3 },
      F.totals(METRICS)
    )
  end

  def test_totals_without_data_do_not_divide_by_zero
    totals = F.totals({})
    assert_equal 0, totals["aov_cents"]
    assert_equal 0.0, totals["conversion_rate"]
  end

  def test_aov_rounds_to_a_whole_cent
    assert_equal 3333, F.totals("orders" => 3, "revenue_cents" => 10_000)["aov_cents"]
  end

  def test_otp_recovery_and_offer_blocks
    assert_equal({ "sent" => 50, "verified" => 45, "bypassed" => 2, "verification_rate" => 90.0 }, F.otp(METRICS))
    assert_equal({ "recovery_opens" => 10, "recovered_orders" => 4, "recovery_rate" => 40.0 }, F.recovery(METRICS))
    assert_equal 25.0, F.offers(METRICS)["offer_accept_rate"]
    assert_equal 0.0, F.offers(METRICS)["upsell_accept_rate"]
  end

  def test_rate_and_change
    assert_equal 33.33, F.rate(1, 3)
    assert_equal 0.0, F.rate(5, 0)
    assert_equal 50.0, F.change(150, 100)
    assert_equal(-25.0, F.change(75, 100))
    assert_nil F.change(10, 0)
  end

  def test_series_is_zero_filled_and_ordered
    daily = { "2026-10-02" => { "form_opens" => 5, "orders" => 1, "revenue_cents" => 900 } }
    assert_equal(
      [{ "date" => "2026-10-01", "form_opens" => 0, "orders" => 0, "revenue_cents" => 0 },
       { "date" => "2026-10-02", "form_opens" => 5, "orders" => 1, "revenue_cents" => 900 },
       { "date" => "2026-10-03", "form_opens" => 0, "orders" => 0, "revenue_cents" => 0 }],
      F.series(daily: daily, from: "2026-10-01", to: Date.new(2026, 10, 3))
    )
  end

  def test_previous_range_has_the_same_length_and_ends_the_day_before
    assert_equal [Date.new(2026, 9, 24), Date.new(2026, 9, 30)], F.previous_range("2026-10-01", "2026-10-07")
    assert_equal [Date.new(2026, 9, 30), Date.new(2026, 9, 30)], F.previous_range("2026-10-01", "2026-10-01")
  end

  def test_normalize_range_defaults_to_last_30_days
    today = Date.new(2026, 10, 3)
    assert_equal [Date.new(2026, 9, 4), today], F.normalize_range(nil, nil, today: today)
  end

  def test_normalize_range_swaps_clamps_and_bounds
    today = Date.new(2026, 10, 3)
    assert_equal [Date.new(2026, 9, 1), Date.new(2026, 9, 5)], F.normalize_range("2026-09-05", "2026-09-01", today: today)
    assert_equal [Date.new(2026, 10, 1), today], F.normalize_range("2026-10-01", "2027-01-01", today: today)
    from, to = F.normalize_range("2020-01-01", "2026-10-03", today: today)
    assert_equal 366, (to - from).to_i + 1
    assert_equal [Date.new(2026, 7, 6), today],
                 F.normalize_range("2026-01-01", "2026-10-03", today: today, earliest: today - 89)
    assert_equal [Date.new(2026, 9, 4), today], F.normalize_range("garbage", "", today: today)
  end

  def test_breakdown_rows_shape_and_order
    rows = F.breakdown_rows(by_value: {
                              "autumn" => { "form_opens" => 100, "orders" => 10, "revenue_cents" => 5000 },
                              "spring" => { "form_opens" => 50, "orders" => 20, "revenue_cents" => 9000 },
                              "empty" => {}
                            })
    assert_equal %w[spring autumn empty], rows.map { |r| r["key"] }
    assert_equal({ "key" => "spring", "form_opens" => 50, "orders" => 20, "revenue_cents" => 9000, "conversion_rate" => 40.0 },
                 rows.first)
  end

  def test_offer_breakdown_adds_views_and_accepts
    rows = F.breakdown_rows(by: "offer", by_value: {
                              "21" => { "offer_views" => 10, "offer_accepts" => 4 },
                              "30" => { "downsell_shown" => 5, "downsell_accepts" => 5 }
                            })
    by_key = rows.to_h { |r| [r["key"], r] }
    assert_equal 10, by_key["21"]["views"]
    assert_equal 40.0, by_key["21"]["accept_rate"]
    assert_equal 100.0, by_key["30"]["accept_rate"]
  end

  def test_breakdown_limit
    by_value = (1..30).to_h { |i| ["k#{i}", { "orders" => i }] }
    assert_equal 5, F.breakdown_rows(by_value: by_value, limit: 5).size
  end

  def test_csv_daily_rows
    daily = { "2026-10-01" => { "form_opens" => 10, "orders" => 2, "revenue_cents" => 123_456, "button_views" => 99 } }
    rows = F.csv_daily_rows(daily: daily, from: "2026-10-01", to: "2026-10-02")
    assert_equal F::CSV_DAILY_COLUMNS, rows.first
    assert_equal 3, rows.size
    first = F::CSV_DAILY_COLUMNS.zip(rows[1]).to_h
    assert_equal "2026-10-01", first["date"]
    assert_equal 99, first["button_views"]
    assert_equal "1234.56", first["revenue"]
    assert_equal "617.28", first["aov"]
    assert_equal 20.0, first["conversion_rate"]
    assert_equal 0, F::CSV_DAILY_COLUMNS.zip(rows[2]).to_h["orders"]
  end

  def test_csv_text_quotes_and_neutralises_formulas
    rows = F.csv_breakdown_rows(rows: [{ "key" => "=HYPERLINK(\"x\")", "form_opens" => 1, "orders" => 0,
                                         "revenue_cents" => 0, "conversion_rate" => 0.0 },
                                       { "key" => "a,b", "form_opens" => 2, "orders" => 1, "revenue_cents" => 150,
                                         "conversion_rate" => 50.0 }])
    csv = F.to_csv(rows)
    lines = csv.split("\n")
    assert_equal "key,form_opens,orders,revenue,conversion_rate", lines[0]
    assert_equal "\"'=HYPERLINK(\"\"x\"\")\",1,0,0.00,0.0", lines[1]
    assert_equal "\"a,b\",2,1,1.50,50.0", lines[2]
    assert csv.end_with?("\n")
  end

  def test_to_date_accepts_dates_strings_and_times
    assert_equal Date.new(2026, 10, 3), F.to_date("2026-10-03T10:00:00Z")
    assert_equal Date.new(2026, 10, 3), F.to_date(Time.utc(2026, 10, 3, 23, 0, 0))
    assert_nil F.to_date("")
    assert_nil F.to_date("not a date")
  end
  def test_offer_rows_join_names_and_sort_by_views
    by_value = {
      "7" => { "offer_views" => 40, "offer_accepts" => 10, "orders" => 6, "revenue_cents" => 90_000 },
      "9" => { "downsell_shown" => 50, "downsell_accepts" => 5 },
      "12" => { "upsell_views" => 4, "upsell_accepts" => 1 },
      "13" => { "form_opens" => 3 }
    }
    offers = { "7" => { "name" => "Buy 2", "offer_type" => "quantity", "status" => "active" },
               "9" => { "name" => "Stay 10%", "offer_type" => "downsell", "status" => "paused" } }
    rows = CodForm::Analytics::Funnel.offer_rows(by_value: by_value, offers: offers)
    assert_equal %w[9 7 12], rows.map { |row| row["id"] }
    assert_equal({ "id" => "7", "name" => "Buy 2", "offer_type" => "quantity", "status" => "active", "views" => 40,
                   "accepts" => 10, "accept_rate" => 25.0, "orders" => 6, "revenue_cents" => 90_000 }, rows[1])
    assert_equal 10.0, rows[0]["accept_rate"]
    assert_nil rows[2]["name"]
    assert_equal [], CodForm::Analytics::Funnel.offer_rows(by_value: nil)
  end

end
