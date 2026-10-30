# frozen_string_literal: true

require "csv"
require "bigdecimal"

module CodForm
  # CSV import of province-wise shipping rates (SHP-8, D.15 `POST /cod_form/shipping_rates/import_csv`).
  #
  # Columns (header row required, any order, case-insensitive; unknown columns are ignored):
  #   name, description, price, country, province, min_total, max_total
  #   - price / min_total / max_total: decimal amounts in the shop currency ("1490", "1490.50",
  #     "1 490,50"); stored as integer cents (amount × 100, 0.1).
  #   - country: ISO 3166-1 alpha-2. province: a province code ("BU" or "HU-BU"); several codes in
  #     one cell are separated by "|". Empty = the whole country.
  #
  # One rate per row. Row numbers in errors are file line numbers (the header is row 1).
  # `parse` is pure and unit-tested without Rails: ruby test/services/cod_form/shipping_csv_importer_test.rb
  class ShippingCsvImporter
    COLUMNS = %w[name description price country province min_total max_total].freeze
    REQUIRED_COLUMNS = %w[name price].freeze
    MODES = %w[append replace].freeze
    MAX_ROWS = 2_000
    MAX_BYTES = 1_048_576
    MAX_ERRORS = 100
    MAX_CENTS = 99_999_999_999
    COUNTRY_RE = /\A[A-Z]{2}\z/.freeze
    PROVINCE_RE = /\A[A-Z0-9]{1,10}\z/.freeze

    class << self
      # => {"created" => Integer, "errors" => [{"row" => Integer, "message" => String}]}
      # replace: every existing rate of the shop is removed, but only when the file has no row
      # error (a half-imported table must never replace a working one). append: valid rows are
      # added, invalid rows are reported.
      def call(shop:, content:, mode: "append")
        mode = MODES.include?(mode.to_s) ? mode.to_s : "append"
        parsed = parse(content)
        rows = parsed["rows"]
        errors = parsed["errors"]
        return { "created" => 0, "errors" => errors } if rows.empty? || (mode == "replace" && errors.any?)

        now = Time.current
        CodForm::ShippingRate.transaction do
          scope = CodForm::ShippingRate.where(shop_id: shop.id)
          scope.delete_all if mode == "replace"
          start = mode == "replace" ? 0 : (scope.maximum(:position) || -1) + 1
          records = rows.each_with_index.map do |row, index|
            row.merge("shop_id" => shop.id, "currency" => nil, "position" => start + index, "active" => true,
                      "source" => CodForm::ShippingRate::SOURCE_CSV, "created_at" => now, "updated_at" => now)
          end
          CodForm::ShippingRate.insert_all(records)
        end
        { "created" => rows.size, "errors" => errors }
      end

      # Pure. => {"rows" => [{"name","description","price_cents","conditions"}], "errors" => [{"row","message"}]}
      def parse(content)
        text = content.to_s
        return failure(1, "The file is larger than 1 MB.") if text.bytesize > MAX_BYTES

        text = text.dup.force_encoding(Encoding::UTF_8)
        text = text.encode(Encoding::UTF_8, Encoding::ISO_8859_1) unless text.valid_encoding?
        text = text.sub(/\A﻿/, "")
        return failure(1, "The file is empty.") if text.strip.empty?

        table = CSV.parse(text, col_sep: separator(text), skip_blanks: false, liberal_parsing: true)
        header = Array(table.first).map { |cell| cell.to_s.strip.downcase }
        missing = REQUIRED_COLUMNS - header
        return failure(1, "Missing column: #{missing.join(', ')}. Expected: #{COLUMNS.join(', ')}.") if missing.any?

        index = COLUMNS.each_with_object({}) { |column, map| map[column] = header.index(column) }
        rows = []
        errors = []
        data_rows = 0
        table.each_with_index do |cells, position|
          next if position.zero?
          next if cells.nil? || cells.all? { |cell| cell.to_s.strip.empty? }

          data_rows += 1
          line = position + 1
          if data_rows > MAX_ROWS
            errors << { "row" => line, "message" => "Only the first #{MAX_ROWS} rows are imported." }
            break
          end
          values = COLUMNS.each_with_object({}) { |column, map| map[column] = index[column] ? cells[index[column]].to_s.strip : "" }
          rate, message = row(values)
          if message
            errors << { "row" => line, "message" => message } if errors.size < MAX_ERRORS
          else
            rows << rate
          end
        end
        errors << { "row" => 1, "message" => "The file has no rate rows." } if data_rows.zero?
        { "rows" => rows, "errors" => errors }
      rescue CSV::MalformedCSVError => e
        failure(e.respond_to?(:line_number) && e.line_number ? e.line_number : 1, "The file is not a valid CSV.")
      end

      # => [rate hash, nil] or [nil, message]
      def row(values)
        return [nil, "Name is required."] if values["name"].empty?
        return [nil, "Name is too long (maximum 100 characters)."] if values["name"].length > 100
        return [nil, "Description is too long (maximum 200 characters)."] if values["description"].length > 200

        price = cents(values["price"])
        return [nil, "Price is required."] if values["price"].empty?
        return [nil, "Price must be a number that is 0 or more."] if price.nil?

        min = values["min_total"].empty? ? nil : cents(values["min_total"])
        max = values["max_total"].empty? ? nil : cents(values["max_total"])
        return [nil, "Minimum total must be a number that is 0 or more."] if !values["min_total"].empty? && min.nil?
        return [nil, "Maximum total must be a number that is 0 or more."] if !values["max_total"].empty? && max.nil?
        return [nil, "Maximum total must not be less than the minimum total."] if min && max && max < min

        country = values["country"].upcase
        return [nil, "Country must be a 2-letter code, for example HU."] unless country.empty? || country.match?(COUNTRY_RE)

        provinces, message = provinces(values["province"], country)
        return [nil, message] if message

        conditions = {
          "countries" => country.empty? ? [] : [country], "provinces" => provinces,
          "subtotal_min_cents" => min, "subtotal_max_cents" => max,
          "weight_min_grams" => nil, "weight_max_grams" => nil,
          "quantity_min" => nil, "quantity_max" => nil,
          "products" => { "mode" => "any", "product_ids" => [], "collection_ids" => [] }
        }
        [{ "name" => values["name"], "description" => values["description"].empty? ? nil : values["description"],
           "price_cents" => price, "conditions" => conditions }, nil]
      end

      # "BU" / "HU-BU" / "BU|PE" → ["HU-BU", "HU-PE"]
      def provinces(cell, country)
        codes = cell.split("|").map { |code| code.strip.upcase }.reject(&:empty?)
        return [[], nil] if codes.empty?
        return [nil, "Country is required when a province is given."] if country.empty?

        list = codes.map do |code|
          code = code.sub(/\A#{country}-/, "")
          return [nil, "Province must be a province code, for example BU or #{country}-BU."] unless code.match?(PROVINCE_RE)

          "#{country}-#{code}"
        end
        [list.uniq, nil]
      end

      # Decimal amount → integer cents; nil when it is not a non-negative number.
      def cents(text)
        value = text.to_s.gsub(/[\s ']/, "")
        if value.include?(",") && value.include?(".")
          value = value.rindex(",") > value.rindex(".") ? value.delete(".").tr(",", ".") : value.delete(",")
        elsif value.count(",") == 1 && value.match?(/,\d{1,2}\z/)
          value = value.tr(",", ".")
        else
          value = value.delete(",")
        end
        return nil unless value.match?(/\A\d{1,12}(\.\d{1,4})?\z/)

        amount = (BigDecimal(value) * 100).round
        amount > MAX_CENTS ? nil : amount.to_i
      end

      private

      def separator(text)
        first_line = text.each_line.first.to_s
        first_line.count(";") > first_line.count(",") ? ";" : ","
      end

      def failure(row, message)
        { "rows" => [], "errors" => [{ "row" => row, "message" => message }] }
      end
    end
  end
end
