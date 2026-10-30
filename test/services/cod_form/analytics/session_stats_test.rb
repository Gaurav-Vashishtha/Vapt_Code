# frozen_string_literal: true

require "minitest/autorun"
require "date"
require_relative "../../../../app/services/cod_form/analytics/funnel"
require_relative "../../../../app/services/cod_form/analytics/session_stats"

class CodFormAnalyticsSessionStatsTest < Minitest::Test
  S = CodForm::Analytics::SessionStats

  ROWS = [
    ["2026-10-01", "ordered", "product", "mobile", "IN", 4, 400_000],
    ["2026-10-01", "open", "product", "mobile", "IN", 5, 0],
    ["2026-10-01", "abandoned", "cart", "desktop", "IN", 3, 0],
    ["2026-10-02", "ordered", "cart", "desktop", "AE", 1, 250_000],
    ["2026-10-02", "handoff_prepaid", "product", "mobile", "IN", 2, 0],
    ["2026-10-02", "blocked", "product", nil, "", 1, 0]
  ].freeze

  def test_totals_series_and_tables
    out = S.summarize(ROWS, from: Date.new(2026, 10, 1), to: Date.new(2026, 10, 3))
    totals = out["totals"]
    assert_equal [16, 5, 650_000, 2, 1], totals.values_at("sessions", "orders", "revenue_cents", "handoffs", "blocked")
    assert_equal 8, totals["abandoned"], "everything that neither ordered, went to pay online, nor was blocked"
    assert_equal [31.25, 50.0, 130_000], totals.values_at("conversion_rate", "abandonment_rate", "aov_cents")

    assert_equal %w[2026-10-01 2026-10-02 2026-10-03], out["series"].map { |d| d["date"] }
    assert_equal [[12, 4], [4, 1], [0, 0]], out["series"].map { |d| d.values_at("sessions", "orders") }

    assert_equal [["product", 12, 4], ["cart", 4, 1]], out["by_source"].map { |r| r.values_at("key", "sessions", "orders") }
    assert_equal %w[mobile desktop unknown], out["by_device"].map { |r| r["key"] }
    assert_equal [["IN", 14], ["AE", 1], ["unknown", 1]], out["by_country"].map { |r| r.values_at("key", "sessions") }
    assert_equal({ "ordered" => 5, "open" => 5, "abandoned" => 3, "handoff_prepaid" => 2, "blocked" => 1 },
                 out["by_status"].to_h { |r| [r["key"], r["sessions"]] })
    assert_equal({ "from" => "2026-10-01", "to" => "2026-10-03" }, out["range"])
  end

  def test_no_sessions
    out = S.summarize([], from: Date.new(2026, 10, 1), to: Date.new(2026, 10, 1))
    assert_equal [0, 0, 0.0, 0.0, 0], out["totals"].values_at("sessions", "orders", "conversion_rate", "abandonment_rate", "aov_cents")
    assert_equal [], out["by_source"]
  end
end
