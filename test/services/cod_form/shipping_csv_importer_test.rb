# frozen_string_literal: true

# Plain minitest, no Rails: ruby test/services/cod_form/shipping_csv_importer_test.rb
require_relative "support/plain_boot"
require_relative "../../../app/services/cod_form/shipping_csv_importer"

class CodFormShippingCsvImporterTest < Minitest::Test
  Importer = CodForm::ShippingCsvImporter

  def test_province_wise_rates
    csv = <<~CSV
      name,description,price,country,province,min_total,max_total
      Budapest,1-2 days,990,HU,BU,,
      Pest megye,2-3 days,1490.50,hu,HU-PE,,19999.99
      Free over 20k,,0,HU,,20000,
      Two provinces,,1200,HU,BU|PE,,
    CSV
    result = Importer.parse(csv)
    assert_empty result["errors"]
    assert_equal 4, result["rows"].size

    first = result["rows"][0]
    assert_equal "Budapest", first["name"]
    assert_equal "1-2 days", first["description"]
    assert_equal 99_000, first["price_cents"]
    assert_equal ["HU"], first["conditions"]["countries"]
    assert_equal ["HU-BU"], first["conditions"]["provinces"]
    assert_equal({ "mode" => "any", "product_ids" => [], "collection_ids" => [] }, first["conditions"]["products"])

    second = result["rows"][1]
    assert_equal 149_050, second["price_cents"]
    assert_equal ["HU-PE"], second["conditions"]["provinces"]
    assert_equal 1_999_999, second["conditions"]["subtotal_max_cents"]

    third = result["rows"][2]
    assert_nil third["description"]
    assert_equal 0, third["price_cents"]
    assert_equal [], third["conditions"]["provinces"]
    assert_equal 2_000_000, third["conditions"]["subtotal_min_cents"]
    assert_nil third["conditions"]["subtotal_max_cents"]

    assert_equal %w[HU-BU HU-PE], result["rows"][3]["conditions"]["provinces"]
  end

  def test_row_level_errors_use_file_line_numbers
    csv = <<~CSV
      name,description,price,country,province,min_total,max_total
      Good,,100,HU,,,
      ,,100,HU,,,
      No price,,,HU,,,
      Bad price,,abc,HU,,,
      Negative,,-5,HU,,,
      Bad country,,100,Hungary,,,
      Province without country,,100,,BU,,
      Bad range,,100,HU,,500,100

      Also good,,0,CO,,,
    CSV
    result = Importer.parse(csv)
    assert_equal %w[Good Also\ good], result["rows"].map { |row| row["name"] }
    assert_equal [3, 4, 5, 6, 7, 8, 9], result["errors"].map { |error| error["row"] }
    assert_equal "Name is required.", result["errors"][0]["message"]
    assert_equal "Price is required.", result["errors"][1]["message"]
    assert_match(/Price must be a number/, result["errors"][2]["message"])
    assert_match(/Country must be a 2-letter code/, result["errors"][4]["message"])
    assert_match(/Country is required/, result["errors"][5]["message"])
    assert_match(/Maximum total/, result["errors"][6]["message"])
  end

  def test_header_is_required_and_flexible
    missing = Importer.parse("title,cost\nA,1\n")
    assert_equal [], missing["rows"]
    assert_equal 1, missing["errors"][0]["row"]
    assert_match(/Missing column: name, price/, missing["errors"][0]["message"])

    reordered = Importer.parse("﻿Price;Name;Extra\n12,50;Semicolons;x\n")
    assert_empty reordered["errors"]
    assert_equal "Semicolons", reordered["rows"][0]["name"]
    assert_equal 1_250, reordered["rows"][0]["price_cents"]
    assert_equal [], reordered["rows"][0]["conditions"]["countries"]
  end

  def test_empty_and_header_only_files
    assert_equal "The file is empty.", Importer.parse("  \n")["errors"][0]["message"]
    assert_equal "The file is empty.", Importer.parse(nil)["errors"][0]["message"]
    assert_equal "The file has no rate rows.", Importer.parse("name,price\n")["errors"][0]["message"]
  end

  def test_size_and_row_limits
    assert_match(/larger than 1 MB/, Importer.parse("name,price\n" + ("x" * 1_048_577))["errors"][0]["message"])

    rows = (1..2_001).map { |n| "Rate #{n},1" }.join("\n")
    result = Importer.parse("name,price\n#{rows}\n")
    assert_equal 2_000, result["rows"].size
    assert_equal 2_002, result["errors"].last["row"]
    assert_match(/first 2000 rows/, result["errors"].last["message"])
  end

  def test_malformed_csv
    result = Importer.parse("name,price\n\"unclosed,1\n")
    assert_equal [], result["rows"]
    assert_equal 1, result["errors"].size
  end

  def test_cents
    assert_equal 149_000, Importer.cents("1490")
    assert_equal 149_050, Importer.cents("1490.50")
    assert_equal 149_050, Importer.cents("1 490,50")
    assert_equal 149_050, Importer.cents("1,490.50")
    assert_equal 149_050, Importer.cents("1.490,50")
    assert_equal 149_000, Importer.cents("1,490")
    assert_equal 5, Importer.cents("0.05")
    assert_equal 0, Importer.cents("0")
    assert_nil Importer.cents("-1")
    assert_nil Importer.cents("12abc")
    assert_nil Importer.cents("")
    assert_nil Importer.cents("99999999999999")
  end

  def test_provinces
    assert_equal [%w[HU-BU], nil], Importer.provinces("bu", "HU")
    assert_equal [%w[HU-BU HU-PE], nil], Importer.provinces("HU-BU | pe | BU", "HU")
    assert_equal [[], nil], Importer.provinces("", "HU")
    assert_nil Importer.provinces("Buda pest", "HU")[0]
    assert_nil Importer.provinces("BU", "")[0]
  end
end
