class StatsJobs::PersistentSigninTallyJob
  include Sidekiq::Worker
  sidekiq_options queue: 'low', retry: 2

  def perform(hit)
    return unless PersistentSigninTally.enabled?

    PersistentSigninTally.record(hit)
  end
end
