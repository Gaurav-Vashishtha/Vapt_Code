# frozen_string_literal: true

require_relative "../support/plain_boot"
require_relative "../../../../app/services/cod_form/integrations/google_sheets/row_builder"

class CodFormSheetsRowBuilderTest < Minitest::Test
  RB = CodForm::Integrations::GoogleSheets::RowBuilder

  SESSION = {
    "order_id" => "6123456789", "order_name" => "#1042", "ordered_at" => "2026-10-03 11:58:00",
    "order_total_cents" => 648_640, "currency" => "HUF",
    "contact" => { "first_name" => "Anna", "last_name" => "Kiss", "phone_e164" => "+36301234567", "email" => "anna@example.com" },
    "address" => { "address1" => "Fő utca 1", "address2" => "", "city" => "Budapest", "province" => "BU", "zip" => "1051", "country" => "HU" },
    "attribution" => { "utm_source" => "fb", "utm_medium" => "paid", "utm_campaign" => "autumn" },
    "custom_fields" => { "cf_a1b2c3d4" => "=cmd|' /C calc'!A0", "note" => "Leave at the door" },
    "quote_snapshot" => {
      "currency" => "HUF", "subtotal_cents" => 599_700, "discount_total_cents" => 199_960, "shipping_cents" => 149_000,
      "total_cents" => 648_640, "cod_fee" => { "amount_cents" => 50_000 }, "discount_code" => { "code" => "WELCOME10" },
      "shipping" => { "selected_id" => 4, "rates" => [{ "id" => 2, "name" => "Express" }, { "id" => 4, "name" => "Standard delivery" }] },
      "lines" => [{ "title" => "Widget", "variant_title" => "Blue", "quantity" => 3 }],
      "extra_lines" => [{ "kind" => "bump", "title" => "Express handling", "quantity" => 1 }]
    }
  }.freeze

  def row(columns)
    RB.build(columns: columns, session: SESSION)
  end

  def test_every_documented_column_key_is_supported
    documented = %w[order_name order_id created_at first_name last_name phone email address1 address2 city province zip
                    country items quantity subtotal discount shipping cod_fee total currency shipping_rate discount_code
                    utm_source utm_medium utm_campaign note]
    assert_equal documented, RB::COLUMN_KEYS
    documented.each { |key| assert RB.valid_column?(key), key }
    assert RB.valid_column?("custom:cf_a1b2c3d4")
    assert RB.valid_column?("customer_name")
    refute RB.valid_column?("custom:")
    refute RB.valid_column?("password")
  end

  def test_row_follows_the_column_mapping_order
    assert_equal ["#1042", "2026-10-03 11:58:00", "Anna Kiss", 6486.4, "HUF"],
                 row(%w[order_name created_at customer_name total currency])
    assert_equal ["HUF", "#1042"], row(%w[currency order_name])
  end

  def test_all_values
    values = RB::COLUMN_KEYS.zip(row(RB::COLUMN_KEYS)).to_h
    assert_equal "6123456789", values["order_id"]
    assert_equal "Anna", values["first_name"]
    assert_equal "'+36301234567", values["phone"], "kept as text, not turned into a number or formula"
    assert_equal "Fő utca 1", values["address1"]
    assert_equal "", values["address2"]
    assert_equal "3 x Widget - Blue, 1 x Express handling", values["items"]
    assert_equal 3, values["quantity"]
    assert_equal 5997.0, values["subtotal"]
    assert_equal 1999.6, values["discount"]
    assert_equal 1490.0, values["shipping"]
    assert_equal 500.0, values["cod_fee"]
    assert_equal 6486.4, values["total"]
    assert_equal "Standard delivery", values["shipping_rate"]
    assert_equal "WELCOME10", values["discount_code"]
    assert_equal "autumn", values["utm_campaign"]
    assert_equal "Leave at the door", values["note"]
  end

  def test_custom_field_columns_and_formula_injection
    assert_equal ["'=cmd|' /C calc'!A0"], row(["custom:cf_a1b2c3d4"])
    assert_equal [""], row(["custom:missing"])
  end

  def test_cell_escaping
    assert_equal "'=1+1", RB.cell("=1+1")
    assert_equal "'-5", RB.cell("-5")
    assert_equal "'@x", RB.cell("@x")
    assert_equal "plain", RB.cell("plain")
    assert_equal 12.5, RB.cell(12.5)
    assert_equal "", RB.cell(nil)
    assert_equal 2000, RB.cell("a" * 5000).length
    assert_equal "ab", RB.cell("a\u0000b")
  end

  def test_unknown_columns_are_dropped_and_empty_mapping_uses_defaults
    assert_equal ["#1042"], row(%w[bogus order_name order_name])
    assert_equal RB::DEFAULT_COLUMNS.size, row([]).size
    assert_equal RB::DEFAULT_COLUMNS.size, row(nil).size
  end

  def test_header_matches_the_mapping
    assert_equal ["Order", "Customer", "cf_a1b2c3d4", "COD fee"], RB.header(%w[order_name customer_name custom:cf_a1b2c3d4 cod_fee])
    assert_equal row(RB::DEFAULT_COLUMNS).size, RB.header(nil).size
  end

  def test_empty_session_gives_blank_cells
    assert_equal ["", "", 0, ""], RB.build(columns: %w[order_name total quantity items], session: {})
  end
end
