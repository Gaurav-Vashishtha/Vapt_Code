# frozen_string_literal: true

class PersistentSigninTally
  KEY_PREFIX = 'codk:persistent_hit:'
  HIT_FIELD = 'total_hit'
  MISS_FIELD = 'total_miss'
  KEY_TTL = 3.days.to_i

  HIT_STAT_KEY = 'persistent_signin_hit'
  MISS_STAT_KEY = 'persistent_signin_miss'

  class << self
    # Off unless PERSISTANT_SIGN_IN_ENABLED=true, so hit/miss tracking stays
    # dark until we opt in.
    def enabled?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch("PERSISTANT_SIGN_IN_ENABLED", nil)) == true
    end

    def redis_key(date = Date.current)
      "#{KEY_PREFIX}#{date.strftime('%d/%m/%y')}"
    end

    def record(hit, date: Date.current)
      key = redis_key(date)
      field = hit ? HIT_FIELD : MISS_FIELD

      Sidekiq.redis do |redis|
        redis.hincrby(key, field, 1)
        redis.expire(key, KEY_TTL)
      end
    end

    def read(date = Date.current)
      raw = Sidekiq.redis { |redis| redis.hgetall(redis_key(date)) } || {}
      { hit: raw[HIT_FIELD].to_i, miss: raw[MISS_FIELD].to_i }
    end

    def delete(date)
      Sidekiq.redis { |redis| redis.del(redis_key(date)) }
    end

    def pending_keys
      Sidekiq.redis do |redis|
        redis.scan('MATCH', "#{KEY_PREFIX}*").to_a
      end.uniq.sort
    end

    def summary(date = Date.current)
      counts = read(date)
      total = counts[:hit] + counts[:miss]
      counts.merge(
        key: redis_key(date),
        total: total,
        hit_ratio: total.zero? ? 0.0 : (counts[:hit].to_f / total * 100).round(2)
      )
    end
  end
end
