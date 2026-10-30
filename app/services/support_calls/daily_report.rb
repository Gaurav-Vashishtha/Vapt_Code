# frozen_string_literal: true

module SupportCalls
  class DailyReport
    CONNECTED_MISS = %w[not_connected voicemail busy wrong_number].freeze

    def initialize(date = Date.current)
      @date = date
    end

    def to_h
      records = CallRecord.on_date(@date)
      attempted = records.count
      outcomes = records.group(:outcome).count
      connected = attempted - CONNECTED_MISS.sum { |o| outcomes[o].to_i }
      targets = CallTarget.for_date(@date)

      {
        date: @date,
        day_owner: targets.first&.assigned_engineer || DayOwner.for_date(@date),
        target: targets.count.positive? ? targets.count : call_target_count,
        attempted: attempted,
        connected: connected,
        connect_rate: pct(connected, attempted),
        onboarded: outcomes["onboarded"].to_i,
        reonboarded: outcomes["reonboarded"].to_i,
        outcomes: labelled_outcomes(outcomes),
        per_agent: records.group(:agent_name).count.reject { |k, _| k.blank? },
        reminders_due_next: CallReminder.due_by(next_calling_day).count,
        not_reached: targets.pending.ranked.limit(15).to_a
      }
    end

    private

    def labelled_outcomes(outcomes)
      outcomes.sort_by { |_, v| -v }.map { |code, count| [CallRecord::OUTCOME_LABELS.fetch(code, code), count] }
    end

    def next_calling_day
      day = @date + 1
      day += 1 if day.sunday?
      day
    end

    def call_target_count
      ENV.fetch("CALL_TARGET_PER_DAY", QueueBuilder::DEFAULT_TARGET).to_i
    end

    def pct(num, den)
      return 0 if den.to_i.zero?

      ((num.to_f / den) * 100).round
    end
  end
end
