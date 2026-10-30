# frozen_string_literal: true

module Whatsapp
  # Pauses campaigns before they get the sending number restricted. Nothing here
  # ever resumes a campaign: the merchant does that with a confirm step (PM D5).
  module CampaignGuardrails
    REASONS = %w[quality_low failure_spike account_blocked].freeze
    PAUSABLE_STATUSES = %w[scheduled sending retry_waiting].freeze
    # Meta's spam / per-user / throughput limits: a burst of these means the
    # number is being throttled for how it's sending (PM D7).
    HEALTH_CODES = %w[131048 131049 131056 130429].freeze
    # Account locked, policy block, payment issue, number not registered.
    BLOCKING_CODES = %w[131031 368 131042 133010].freeze
    SPIKE_WINDOW = 30.minutes
    SPIKE_MIN_ATTEMPTS = 100
    SPIKE_RATIO = 0.25

    module_function

    def check_account!(account)
      return [] unless account&.quality_low?

      WhatsappCampaign.where(whatsapp_account_id: account.id, status: PAUSABLE_STATUSES)
                      .find_each.select { |campaign| enforce_quality!(campaign, account) }
    end

    def enforce_quality!(campaign, account = campaign.whatsapp_account)
      return false unless account&.quality_low?
      return false if risk_acknowledged?(campaign, account)

      pause!(campaign, 'quality_low', 'quality_rating' => account.quality_rating.to_s.upcase)
    end

    # The merchant's "I understand the risk" holds only for the rating they saw;
    # a later drop to a different low rating pauses again.
    def risk_acknowledged?(campaign, account)
      acked = detail_of(campaign)['risk_acknowledged_rating']
      acked.present? && acked.to_s.upcase == account.quality_rating.to_s.upcase
    end

    def acknowledgement_for(account, at = Time.current)
      { 'risk_acknowledged_rating' => account.quality_rating.to_s.upcase, 'risk_acknowledged_at' => at.iso8601 }
    end

    def check_failure_spike!(campaign)
      since = [SPIKE_WINDOW.ago, resumed_at(campaign)].compact.max
      scope = campaign.recipients.where('last_attempt_at > ?', since)
      attempts = scope.count
      return false if attempts < SPIKE_MIN_ATTEMPTS

      failed = scope.where(status: %w[failed retry_pending], error_code: HEALTH_CODES).count
      return false if failed < attempts * SPIKE_RATIO

      pause!(campaign, 'failure_spike',
             'attempts' => attempts, 'failed' => failed, 'window_minutes' => (SPIKE_WINDOW / 60).to_i)
    end

    def on_send_failure(campaign, code)
      normalized = code.to_s[/\d+/].to_s
      return false unless campaign && BLOCKING_CODES.include?(normalized)

      pause!(campaign, 'account_blocked', 'error_code' => normalized)
    end

    def pause!(campaign, reason, detail = {})
      now = Time.current
      kept = detail_of(campaign).slice('risk_acknowledged_rating', 'risk_acknowledged_at')
      merged = kept.merge(detail.stringify_keys)
      changed = WhatsappCampaign.where(id: campaign.id, status: PAUSABLE_STATUSES)
                                .update_all(status: 'paused', pause_reason: reason, pause_detail: merged,
                                            paused_at: now, updated_at: now)
      return false if changed.zero?

      campaign.assign_attributes(status: 'paused', pause_reason: reason, pause_detail: merged, paused_at: now)
      notify_once(campaign, reason, now)
      true
    rescue StandardError => e
      Rails.logger.error("[Whatsapp::CampaignGuardrails] pause campaign=#{campaign&.id} #{e.class}: #{e.message}")
      false
    end

    def notify_once(campaign, reason, now)
      claimed = WhatsappCampaign.where(id: campaign.id, guardrail_notified_at: nil)
                                .update_all(guardrail_notified_at: now)
      return if claimed.zero?

      WhatsappGuardrailMailer.campaign_paused(campaign.id).deliver_later
      SlackNotifyJob.perform_async(
        ":octagonal_sign: WhatsApp campaign auto-paused (#{Rails.env}) — #{campaign.shop&.shopify_domain} " \
        "campaign=#{campaign.id} \"#{campaign.name}\" reason=#{reason} detail=#{campaign.pause_detail.to_json}"
      )
    rescue StandardError => e
      Rails.logger.error("[Whatsapp::CampaignGuardrails] notify campaign=#{campaign&.id} #{e.class}: #{e.message}")
    end

    def resumed_at(campaign)
      raw = detail_of(campaign)['resumed_at']
      raw.present? ? Time.zone.parse(raw.to_s) : nil
    rescue ArgumentError
      nil
    end

    def detail_of(campaign)
      campaign.pause_detail.is_a?(Hash) ? campaign.pause_detail : {}
    end
  end
end
