module Churn
  # Weekly leadership digest: headline KPIs, retention, top churn reasons, and the
  # biggest at-risk accounts. Emails recipients in CHURN_DIGEST_RECIPIENTS and
  # posts a short summary to Slack.
  class WeeklyDigestJob < ApplicationJob
    sidekiq_options queue: 'administration', retry: 1

    def perform
      metrics = Churn::Metrics.new(days: 7)
      data = {
        kpis: metrics.kpis,
        reasons: metrics.churn_reasons,
        cohorts: metrics.retention_cohorts(months: 3),
        worklist: metrics.at_risk_worklist(limit: 15),
        waterfall: metrics.mrr_waterfall
      }

      recipients = ENV.fetch("CHURN_DIGEST_RECIPIENTS", nil).to_s.split(',').map(&:strip).reject(&:blank?)
      ChurnMailer.weekly_digest(recipients, data).deliver_later if recipients.any?

      k = data[:kpis]
      SlackNotifyJob.perform_async(
        ":chart_with_downwards_trend: *Weekly churn digest (#{Rails.env})*\n" \
        "Active: #{k[:active_shops]} | New: #{k[:new_installs]} | Uninstalls: #{k[:uninstalls]} | " \
        "Logo churn: #{k[:logo_churn_rate]}% | MRR: $#{k[:mrr]} | At-risk: #{k[:at_risk_count]}\n" \
        "Top reasons: #{Array(data[:reasons]).first(3).map { |r, c| "#{r} (#{c})" }.join(', ')}"
      )
    rescue => e
      Rails.logger.error("[Churn::WeeklyDigestJob] #{e.class}: #{e.message}")
    end
  end
end
