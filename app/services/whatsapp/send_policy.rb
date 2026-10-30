# frozen_string_literal: true

module Whatsapp
  # Per-campaign delivery rules. A key missing from campaign.send_policy means
  # the default, so new campaigns get both rules on; campaigns that were already
  # in flight at rollout were backfilled with both disabled.
  module SendPolicy
    DEFAULTS = {
      'quiet_hours' => { 'enabled' => true, 'start_hour' => 21, 'end_hour' => 9 },
      'frequency_cap' => { 'enabled' => true, 'hours' => 48 }
    }.freeze
    MAX_CAP_HOURS = 168
    REDIS_PREFIX = 'wa:fcap'

    module_function

    def sanitize(raw)
      h = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : (raw || {}).to_h
      h = h.deep_stringify_keys
      qh = h['quiet_hours'].is_a?(Hash) ? h['quiet_hours'] : {}
      fc = h['frequency_cap'].is_a?(Hash) ? h['frequency_cap'] : {}
      {
        'quiet_hours' => {
          'enabled' => bool(qh, 'enabled', DEFAULTS['quiet_hours']['enabled']),
          'start_hour' => hour(qh['start_hour'], DEFAULTS['quiet_hours']['start_hour']),
          'end_hour' => hour(qh['end_hour'], DEFAULTS['quiet_hours']['end_hour'])
        },
        'frequency_cap' => {
          'enabled' => bool(fc, 'enabled', DEFAULTS['frequency_cap']['enabled']),
          'hours' => cap_hours(fc['hours'])
        }
      }
    end

    def effective(subject, policy = nil)
      stored = policy || (subject.respond_to?(:send_policy) ? subject.send_policy : nil)
      stored = stored.is_a?(Hash) ? stored.deep_stringify_keys : {}
      DEFAULTS.each_with_object({}) do |(key, defaults), out|
        out[key] = defaults.merge(stored[key].is_a?(Hash) ? stored[key] : {})
      end
    end

    # subject is a WhatsappCampaign or a Shop (store defaults, e.g. for a
    # campaign that isn't saved yet); policy overrides the stored one.
    def in_quiet_hours?(subject, at = Time.current, policy: nil)
      qh = effective(subject, policy)['quiet_hours']
      return false unless qh['enabled'] == true

      start_h = qh['start_hour'].to_i
      end_h = qh['end_hour'].to_i
      return false if start_h == end_h

      h = at.in_time_zone(zone_for(subject)).hour
      start_h < end_h ? (h >= start_h && h < end_h) : (h >= start_h || h < end_h)
    end

    def next_window_start(subject, at = Time.current, policy: nil)
      return at unless in_quiet_hours?(subject, at, policy: policy)

      end_h = effective(subject, policy)['quiet_hours']['end_hour'].to_i
      local = at.in_time_zone(zone_for(subject))
      candidate = local.change(hour: end_h, min: 0, sec: 0)
      candidate += 1.day if candidate <= local
      candidate
    end

    def quiet_hours_label(subject, policy: nil)
      qh = effective(subject, policy)['quiet_hours']
      { start: format_hour(qh['start_hour']), end: format_hour(qh['end_hour']) }
    end

    def frequency_cap_hours(campaign)
      fc = effective(campaign)['frequency_cap']
      fc['enabled'] == true ? cap_hours(fc['hours']) : nil
    end

    # Claims the phone for this campaign in Redis (SET NX). The database check
    # covers a Redis flush or outage. A claim that turns out to be capped is
    # released so it doesn't block other campaigns for the window.
    def frequency_capped?(campaign, recipient)
      hours = frequency_cap_hours(campaign)
      return false unless hours

      claim = redis_claim(campaign, recipient, hours)
      if claim == :held_by_other
        return true unless holder_failed?(campaign, recipient)

        record_send!(campaign, recipient)
        claim = :claimed
      end

      capped = WhatsappCampaignRecipient
               .where(shop_id: campaign.shop_id, phone: recipient.phone)
               .where.not(whatsapp_campaign_id: campaign.id)
               .where.not(status: %w[failed suppressed])
               .where('sent_at > ?', hours.hours.ago)
               .exists?
      release!(campaign, recipient) if capped && claim == :claimed
      capped
    end

    def record_send!(campaign, recipient)
      hours = frequency_cap_hours(campaign)
      return unless hours

      Sidekiq.redis { |r| r.call('SET', redis_key(campaign, recipient), campaign.id.to_s, 'EX', (hours * 3600).to_i.to_s) }
    rescue StandardError => e
      Rails.logger.warn("[Whatsapp::SendPolicy] record_send failed: #{e.class}: #{e.message}")
    end

    def release!(campaign, recipient)
      key = redis_key(campaign, recipient)
      Sidekiq.redis do |r|
        r.call('DEL', key) if r.call('GET', key).to_s == campaign.id.to_s
      end
    rescue StandardError => e
      Rails.logger.warn("[Whatsapp::SendPolicy] release failed: #{e.class}: #{e.message}")
    end

    def holder_failed?(campaign, recipient)
      holder_id = Sidekiq.redis { |r| r.call('GET', redis_key(campaign, recipient)) }.to_i
      return false if holder_id.zero?

      statuses = WhatsappCampaignRecipient.where(whatsapp_campaign_id: holder_id, phone: recipient.phone).pluck(:status)
      statuses.present? && (statuses - %w[failed suppressed]).empty?
    rescue StandardError
      false
    end

    def redis_claim(campaign, recipient, hours)
      key = redis_key(campaign, recipient)
      Sidekiq.redis do |r|
        set = r.call('SET', key, campaign.id.to_s, 'NX', 'EX', (hours * 3600).to_i.to_s)
        next :claimed if set.to_s == 'OK'

        holder = r.call('GET', key).to_s
        holder.present? && holder != campaign.id.to_s ? :held_by_other : :own
      end
    rescue StandardError => e
      Rails.logger.warn("[Whatsapp::SendPolicy] redis claim failed: #{e.class}: #{e.message}")
      :unknown
    end

    def redis_key(campaign, recipient)
      "#{REDIS_PREFIX}:#{campaign.shop_id}:#{recipient.phone}"
    end

    def zone_for(subject)
      shop = subject.is_a?(Shop) ? subject : subject.shop
      ShopTimezone.for(shop)
    end

    def format_hour(hour)
      Time.utc(2000, 1, 1, hour.to_i).strftime('%-l:%M %p')
    end

    def bool(hash, key, default)
      return default unless hash.key?(key)

      ActiveModel::Type::Boolean.new.cast(hash[key]) == true
    end

    def hour(value, default)
      return default if value.blank?

      int = Integer(value.to_s, 10)
      int.between?(0, 23) ? int : default
    rescue ArgumentError, TypeError
      default
    end

    def cap_hours(value)
      int = value.to_i
      int.between?(1, MAX_CAP_HOURS) ? int : DEFAULTS['frequency_cap']['hours']
    end
  end
end
