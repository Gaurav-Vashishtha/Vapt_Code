# frozen_string_literal: true

module SupportCalls
  class QueueBuilder
    DEFAULT_TARGET = 50
    DEFAULT_MIX = { "new_install" => 40, "active" => 30, "churned" => 30 }.freeze
    SEGMENTS = CallTarget::SEGMENTS

    def initialize(date: Date.current)
      @date = date
    end

    def build!(force: false)
      return existing if @date.sunday?

      if CallTarget.for_date(@date).exists?
        return existing unless force

        CallTarget.for_date(@date).delete_all
      end

      roll_forward_sunday_reminders

      collector = CandidateCollector.new(reference_date: @date)
      pool = dedup_by_domain(collector.new_installs + collector.active + collector.churned)

      suppressed = CallSuppression.suppressed_domains.to_set
      pool.reject! { |c| suppressed.include?(c[:domain]) }

      latest = latest_record_by_domain
      due_domains = CallReminder.open_domains_due_by(@date).to_set

      priority, recontact = partition_eligibility(pool, latest, due_domains)

      selected = select_with_mix(priority, due_domains)
      cutoff = selected.map { |c| c[:cps] }.min.to_i
      qualified = recontact.select { |c| c[:cps] >= cutoff * PriorityScorer::RECONTACT_MULTIPLIER }
      selected = select_with_mix(priority + qualified, due_domains) if qualified.any?

      persist(selected)
      existing
    end

    def existing
      CallTarget.for_date(@date).ranked
    end

    # Fills the day's queue back up to the configured daily cap.
    def top_up!
      return existing if @date.sunday?

      targets = CallTarget.for_date(@date)
      return build! unless targets.exists?

      fill!(call_target_count - targets.pending.count)
    end

    # Appends `count` MORE targets on top of what's already there, ignoring the
    # daily cap — the "Get next 50" action for when a day's 50 are exhausted and
    # the caller wants a fresh batch to keep going.
    def add_more!(count)
      return existing if @date.sunday?

      targets = CallTarget.for_date(@date)
      return build! unless targets.exists?

      fill!(count.to_i)
    end

    private

    # Selects up to `delta` fresh candidates (not already queued or suppressed),
    # ranked by call-priority score, and appends them to the day's queue.
    def fill!(delta)
      return existing if delta <= 0

      targets = CallTarget.for_date(@date)
      already = targets.pluck(:shopify_domain).to_set
      suppressed = CallSuppression.suppressed_domains.to_set

      collector = CandidateCollector.new(reference_date: @date)
      pool = dedup_by_domain(collector.new_installs + collector.active + collector.churned)
      pool.reject! { |c| already.include?(c[:domain]) || suppressed.include?(c[:domain]) }

      latest = latest_record_by_domain
      due_domains = CallReminder.open_domains_due_by(@date).to_set
      priority, recontact = partition_eligibility(pool, latest, due_domains)

      chosen = priority.sort_by { |c| -c[:cps] }.first(delta)
      if chosen.size < delta
        cutoff = chosen.map { |c| c[:cps] }.min.to_i
        qualified = recontact.select { |c| c[:cps] >= cutoff * PriorityScorer::RECONTACT_MULTIPLIER }
        chosen += qualified.sort_by { |c| -c[:cps] }.first(delta - chosen.size)
      end
      return existing if chosen.empty?

      owner = targets.first&.assigned_engineer || DayOwner.for_date(@date)
      start_rank = targets.maximum(:rank).to_i
      chosen.each_with_index do |c, index|
        CallTarget.create!(
          call_date: @date, shopify_domain: c[:domain], shop_id: c[:shop_id], segment: c[:segment],
          rank: start_rank + index + 1, cps: c[:cps], value_score: c[:value], urgency_score: c[:urgency],
          reasons: Array(c[:reasons]), assigned_engineer: owner, status: "pending"
        )
      rescue ActiveRecord::RecordNotUnique
        next
      end
      existing
    end

    def dedup_by_domain(candidates)
      best = {}
      candidates.each do |c|
        current = best[c[:domain]]
        best[c[:domain]] = c if current.nil? || c[:cps] > current[:cps]
      end
      best.values
    end

    def latest_record_by_domain
      CallRecord.where(id: CallRecord.group(:shopify_domain).select("MAX(id)")).index_by(&:shopify_domain)
    end

    def partition_eligibility(pool, latest, due_domains)
      priority = []
      recontact = []

      pool.each do |c|
        if due_domains.include?(c[:domain])
          priority << c
          next
        end

        rec = latest[c[:domain]]
        if rec.nil?
          priority << c
          next
        end

        days = (@date - rec.called_at.to_date).to_i
        floor = CallRecord::SHORT_RETRY_OUTCOMES.include?(rec.outcome) ? PriorityScorer::SHORT_COOLDOWN_DAYS : PriorityScorer::COOLDOWN_DAYS

        next if days < floor

        if floor == PriorityScorer::COOLDOWN_DAYS
          recontact << c
        else
          priority << c
        end
      end

      [priority, recontact]
    end

    def select_with_mix(candidates, due_domains)
      target = call_target_count
      mix = mix_counts(target)
      pool = dedup_by_domain(candidates)

      chosen = []
      chosen_domains = Set.new

      pool.select { |c| due_domains.include?(c[:domain]) }
          .sort_by { |c| -c[:cps] }
          .each do |c|
            break if chosen.size >= target
            next if chosen_domains.include?(c[:domain])

            chosen << c.merge(due: true)
            chosen_domains << c[:domain]
          end

      remaining = pool.reject { |c| chosen_domains.include?(c[:domain]) }.sort_by { |c| -c[:cps] }
      by_segment = remaining.group_by { |c| c[:segment] }

      SEGMENTS.each do |segment|
        already = chosen.count { |c| c[:segment] == segment }
        need = [mix[segment].to_i - already, 0].max
        next if need.zero?

        (by_segment[segment] || []).reject { |c| chosen_domains.include?(c[:domain]) }.first(need).each do |c|
          chosen << c
          chosen_domains << c[:domain]
        end
      end

      if chosen.size < target
        remaining.reject { |c| chosen_domains.include?(c[:domain]) }.first(target - chosen.size).each do |c|
          chosen << c
          chosen_domains << c[:domain]
        end
      end

      chosen.sort_by { |c| [c[:due] ? 0 : 1, -c[:cps]] }
    end

    def persist(selected)
      owner = DayOwner.for_date(@date)
      CallTarget.transaction do
        selected.each_with_index do |c, index|
          CallTarget.create!(
            call_date: @date,
            shopify_domain: c[:domain],
            shop_id: c[:shop_id],
            segment: c[:segment],
            rank: index + 1,
            cps: c[:cps],
            value_score: c[:value],
            urgency_score: c[:urgency],
            reasons: Array(c[:reasons]),
            assigned_engineer: owner,
            status: "pending"
          )
        end
      end
    end

    def roll_forward_sunday_reminders
      CallReminder.open_reminders.where("EXTRACT(DOW FROM due_on) = 0").update_all("due_on = due_on + 1, updated_at = NOW()")
    end

    def call_target_count
      value = ENV.fetch("CALL_TARGET_PER_DAY", DEFAULT_TARGET).to_i
      value.positive? ? value : DEFAULT_TARGET
    end

    def mix_counts(target)
      mix = parse_mix
      total = mix.values.sum.to_f
      total = 1.0 if total.zero?
      new_install = (target * mix["new_install"] / total).round
      active = (target * mix["active"] / total).round
      {
        "new_install" => new_install,
        "active" => active,
        "churned" => target - new_install - active
      }
    end

    def parse_mix
      raw = ENV["CALL_MIX"].to_s.split(",").map { |n| n.strip.to_i }
      return DEFAULT_MIX if raw.size != 3 || raw.sum.zero?

      { "new_install" => raw[0], "active" => raw[1], "churned" => raw[2] }
    end
  end
end
