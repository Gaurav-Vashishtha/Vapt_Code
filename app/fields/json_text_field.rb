# frozen_string_literal: true

require "administrate/field/base"
require "json"

# Administrate field for jsonb columns: shown as pretty JSON, edited in a textarea.
# The submitted text is parsed back to a Hash / Array by Admin::CodForm::AdminContext
# (invalid JSON is kept as text, so the model validation reports it and the form shows it again).
class JsonTextField < Administrate::Field::Base
  TRUNCATE_AT = 80

  def self.searchable?
    false
  end

  def to_s
    return "" if data.nil?
    return data if data.is_a?(String)

    JSON.pretty_generate(data.as_json)
  rescue StandardError
    data.to_s
  end

  def compact
    return "" if data.nil?
    return data if data.is_a?(String)

    JSON.generate(data.as_json)
  rescue StandardError
    data.to_s
  end

  def truncate
    text = compact
    text.length > TRUNCATE_AT ? "#{text[0, TRUNCATE_AT]}…" : text
  end

  def rows
    options.fetch(:rows, 8)
  end
end
