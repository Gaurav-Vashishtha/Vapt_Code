# frozen_string_literal: true

module Churn
  # "Load records" on /support_dashboard/risk_customers: computes the list and
  # the revenue header (Churn::RiskCustomers#build!) and caches it in Redis.
  class RiskCustomersJob < ApplicationJob
    sidekiq_options queue: 'default', retry: 0

    def perform(params = {})
      params = (params || {}).symbolize_keys
      Churn::RiskCustomers.new(**params.slice(:installed_within, :min_usage, :rev_from, :rev_to)).build!
    rescue => e
      Rails.logger.error("[Churn::RiskCustomersJob] #{e.class}: #{e.message.to_s.split('#<').first}")
      raise
    end
  end
end
