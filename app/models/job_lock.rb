class JobLock < ApplicationRecord
    # Acquires lock. Returns true if locked, nil if already held.
    # If stale_after is set (e.g. 10.minutes), a lock older than that is cleared and we try again (so killed jobs don't block forever).
    def self.lock!(job_name, stale_after: nil)
      if stale_after.present?
        where(job_name: job_name).where("locked_at < ?", stale_after.ago).delete_all
      end
      create!(job_name: job_name, locked_at: Time.current)
      true
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    # Updates locked_at to now. Use from a long-running job so the lock isn't treated as stale (e.g. heartbeat every 30 min).
    def self.touch!(job_name)
      where(job_name: job_name).update_all(locked_at: Time.current)
    end

    def self.unlock!(job_name)
      where(job_name: job_name).delete_all
    end

    def self.locked?(job_name)
      exists?(job_name: job_name)
    end
  end
  