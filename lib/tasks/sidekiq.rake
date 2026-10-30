namespace :sidekiq do
  desc "Delete stale jobs"
  task :delete_old_jobs, [] => :environment do |t, args|
    SidekiqJobs::DeleteOldJob.perform_async()
  end
end
