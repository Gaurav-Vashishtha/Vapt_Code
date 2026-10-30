class StatsJobs::PersistentSigninFlushJob
  include Sidekiq::Worker
  sidekiq_options queue: 'administration', retry: 2

  LOOKBACK_DAYS = 2

  def perform
    return unless PersistentSigninTally.enabled?

    today = Date.current

    (0..LOOKBACK_DAYS).each do |offset|
      date = today - offset
      counts = PersistentSigninTally.read(date)
      next if counts[:hit].zero? && counts[:miss].zero?

      CodKingStat.update_stat(
        PersistentSigninTally::HIT_STAT_KEY, counts[:hit],
        operation: :set, stat_date: date
      )
      CodKingStat.update_stat(
        PersistentSigninTally::MISS_STAT_KEY, counts[:miss],
        operation: :set, stat_date: date
      )

      PersistentSigninTally.delete(date) if date < today
    end
  end
end
