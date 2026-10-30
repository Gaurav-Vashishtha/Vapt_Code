# frozen_string_literal: true

module Rto
  class BackfillLeaseManager
    DEFAULT_TTL = 30.minutes

    def self.parallelism
      (ENV["BACKFILL_PARALLELISM"].presence || "5").to_i.clamp(1, 100)
    end

    def self.acquire_for!(shop_domain_id, ttl: DEFAULT_TTL)
      BackfillLease.expired.delete_all

      BackfillLease.transaction do
        # Postgres does not allow `FOR UPDATE` on aggregate queries like COUNT(*).
        # We lock the active rows instead and count them in-memory.
        active_leases = BackfillLease.where("expires_at >= ?", Time.current).lock.to_a
        active_count = active_leases.size
        return nil if active_count >= parallelism

        lease_key = "backfill:shop_domain:#{shop_domain_id}"
        expires_at = Time.current + ttl

        # Ensure at most one active lease per domain.
        existing = BackfillLease.lock.find_by(lease_key: lease_key)
        if existing.present?
          return nil unless existing.expired?
          existing.update!(expires_at: expires_at)
          return existing
        end

        BackfillLease.create!(shop_domain_id: shop_domain_id, lease_key: lease_key, expires_at: expires_at)
      end
    end

    def self.release!(lease)
      lease&.destroy
    rescue
      nil
    end
  end
end

