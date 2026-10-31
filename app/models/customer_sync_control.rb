# frozen_string_literal: true

class CustomerSyncControl < ApplicationRecord
  MODES = %w[running paused killed].freeze
  CACHE_SECONDS = 5

  class << self
    def mode
      cached = @cache
      return cached[:mode] if cached && Time.current - cached[:at] < CACHE_SECONDS

      value = where(name: 'global').pick(:mode) || 'running'
      @cache = { mode: value, at: Time.current }
      value
    rescue StandardError
      'paused'
    end

    def fresh_mode
      @cache = nil
      mode
    end

    def killed? = mode == 'killed'

    def paused? = mode != 'running'

    def set!(new_mode, reason: nil, by: 'console')
      raise ArgumentError, "mode must be one of #{MODES.join(', ')}" unless MODES.include?(new_mode.to_s)

      row.update!(mode: new_mode.to_s, reason: reason, changed_by: by, changed_at: Time.current)
      @cache = { mode: new_mode.to_s, at: Time.current }
      row
    end

    def beat!
      where(name: 'global').update_all(coordinator_heartbeat_at: Time.current)
    end

    def row
      find_or_create_by!(name: 'global')
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def kill!(reason = nil, by: 'console') = set!('killed', reason: reason, by: by)

    def pause!(reason = nil, by: 'console') = set!('paused', reason: reason, by: by)

    def resume!(by: 'console') = set!('running', reason: nil, by: by)
  end
end
