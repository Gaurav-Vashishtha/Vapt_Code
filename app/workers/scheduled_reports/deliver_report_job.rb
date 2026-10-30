# frozen_string_literal: true

module ScheduledReports
  class DeliverReportJob
    include Sidekiq::Job

    MAIL_LOCK = "scheduled_report_email_send"
    MAIL_STALE = 45.minutes
    DRAIN_POLL_TIMEOUT = 30.minutes

    sidekiq_options queue: :scheduled_report_delivery, retry: 2

    # Second argument hash:
    # - "send_now" => true — test/immediate send; does not update last_sent_on.
    # - "from_drain" => true — synchronous call from DrainDueScheduledReportsJob; waits for MAIL_LOCK.
    def perform(report_id, opts = nil)
      options = normalize_opts(opts)
      send_now = options[:send_now]
      from_drain = options[:from_drain]

      acquired = false
      if from_drain
        unless wait_for_mail_lock!
          Rails.logger.error("[DeliverReportJob] mail lock wait timeout report_id=#{report_id}")
          return
        end
        acquired = true
      elsif JobLock.lock!(MAIL_LOCK, stale_after: MAIL_STALE)
        acquired = true
      else
        self.class.perform_in(20.seconds, report_id, stringify_opts_for_retry(opts))
        return
      end

      run_deliver(report_id, send_now: send_now)
    ensure
      JobLock.unlock!(MAIL_LOCK) if acquired
    end

    private

    def wait_for_mail_lock!
      deadline = DRAIN_POLL_TIMEOUT.from_now
      loop do
        return true if JobLock.lock!(MAIL_LOCK, stale_after: MAIL_STALE)

        return false if Time.current > deadline

        sleep(0.2)
      end
    end

    def run_deliver(report_id, send_now:)
      report = ScheduledShopReport.find_by(id: report_id)
      return if report.blank?

      tz = report.deliver_timezone
      local_date = Time.current.in_time_zone(tz).to_date
      manage_url = ManageReportsUrl.for_shop(report.shop)

      report.with_lock do
        report.reload
        unless report.effective_enabled?
          Rails.logger.info("[DeliverReportJob] skipped (disabled) report_id=#{report_id}")
          next
        end
        unless report.feature_ready?
          Rails.logger.info("[DeliverReportJob] skipped (feature off) report_id=#{report_id}")
          next
        end
        unless send_now
          if report.last_sent_on == local_date
            Rails.logger.info("[DeliverReportJob] skipped (already sent) report_id=#{report_id} date=#{local_date}")
            next
          end
        end

        recipients = report.recipient_list
        if recipients.blank?
          Rails.logger.warn("[DeliverReportJob] skipped (no recipients) report_id=#{report_id}")
          next
        end

        payload = ReportContent.build(report)

        ShopReportMailer.scheduled_report(
          recipients,
          payload.subject,
          payload.body_text,
          payload.body_html,
          payload.attachment_name,
          payload.attachment_content,
          manage_reports_url: manage_url,
        ).deliver_now

        ScheduledReportDelivery.create!(
          shop: report.shop,
          scheduled_shop_report: report,
          scheduled_report_definition: report.scheduled_report_definition,
          report_kind: report.report_kind.to_s,
          send_now: send_now,
          sent_at: Time.current,
          recipients: recipients.join(", "),
          subject: payload.subject.to_s,
          status: "sent",
        )

        report.update_column(:last_sent_on, local_date) unless send_now
      end
    rescue StandardError => e
      begin
        report = ScheduledShopReport.find_by(id: report_id)
        if report.present?
          ScheduledReportDelivery.create!(
            shop: report.shop,
            scheduled_shop_report: report,
            scheduled_report_definition: report.scheduled_report_definition,
            report_kind: report.report_kind.to_s,
            send_now: send_now,
            sent_at: Time.current,
            recipients: report.recipient_list.join(", "),
            subject: nil,
            status: "failed",
            error_message: "#{e.class}: #{e.message}",
          )
        end
      rescue StandardError
        # ignore logging failures; the original error will still surface
      end
      Rails.logger.error("[DeliverReportJob] report_id=#{report_id} #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      raise e
    end

    def normalize_opts(opts)
      return { send_now: false, from_drain: false } if opts.blank?

      h = opts.respond_to?(:symbolize_keys) ? opts.symbolize_keys : opts
      {
        send_now: h[:send_now] == true || h["send_now"] == true,
        from_drain: h[:from_drain] == true || h["from_drain"] == true,
      }
    end

    def stringify_opts_for_retry(opts)
      case opts
      when Hash
        opts.stringify_keys
      when nil
        {}
      else
        {}
      end
    end
  end
end
