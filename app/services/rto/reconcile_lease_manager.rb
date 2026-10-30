# frozen_string_literal: true

module Rto
  class ReconcileLeaseManager
    DEFAULT_TTL = 30.minutes
    LEASE_PREFIX = "reconcile:shop_domain:"

    def self.acquire_for!(shop_domain_id, ttl: DEFAULT_TTL)
      BackfillLease.expired.delete_all

      BackfillLease.transaction do
        active_leases = BackfillLease.where("expires_at >= ? AND lease_key LIKE ?", Time.current, "#{LEASE_PREFIX}%").lock.to_a
        active_count = active_leases.size
        return nil if active_count >= BackfillLeaseManager.parallelism

        lease_key = "#{LEASE_PREFIX}#{shop_domain_id}"
        expires_at = Time.current + ttl

        existing = BackfillLease.lock.find_by(lease_key: lease_key)
        if existing.present?
          return nil unless existing.expired?
          existing.update!(expires_at: expires_at)
          return existing
        end

        BackfillLease.create!(shop_domain_id: shop_domain_id, lease_key: lease_key, expires_at: expires_at)
      end
    end

    def self.active_count
      BackfillLease.where("expires_at >= ? AND lease_key LIKE ?", Time.current, "#{LEASE_PREFIX}%").count
    end

    def self.release!(lease)
      BackfillLeaseManager.release!(lease)
    end
  end
end

