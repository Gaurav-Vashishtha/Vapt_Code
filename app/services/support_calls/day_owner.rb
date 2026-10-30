# frozen_string_literal: true

module SupportCalls
  module DayOwner
    module_function

    EPOCH = Date.new(2024, 1, 1)

    def pool
      ENV.fetch("SUPPORT_ENGINEERS", "").split(",").map(&:strip).reject(&:blank?)
    end

    def for_date(date)
      people = pool
      return nil if people.empty?

      people[calling_day_index(date) % people.size]
    end

    def calling_day_index(date)
      return 0 if date <= EPOCH

      total_days = (date - EPOCH).to_i
      full_weeks = total_days / 7
      remainder = total_days % 7
      sundays = full_weeks
      remainder.times do |offset|
        sundays += 1 if (EPOCH + (full_weeks * 7) + offset).sunday?
      end
      total_days - sundays
    end
  end
end
