# frozen_string_literal: true

require "csv"

module ScheduledReports
  class ReportContent
    Result = Struct.new(:subject, :body_text, :body_html, :attachment_name, :attachment_content, keyword_init: true)

    def self.build(report)
      new(report).build
    end

    def initialize(report)
      @report = report
      @shop = report.shop
    end

    def build
      inner =
        if normalized_sql_metrics.any?
          multi_sql_report
        elsif @report.sql_text.present?
          custom_sql_report
        else
          case @report.report_kind
          when "delivery_status_ratio"
            delivery_status_ratio
          when "abandoned_cart_messages"
            abandoned_cart_messages
          when "preorder_otp_cart_csv_24h"
            preorder_otp_csv
          else
            custom_sql_report
          end
        end

      apply_definition_email_prefixes(inner)
    end

    private

    def definition
      @report.scheduled_report_definition
    end

    def normalized_sql_metrics
      @normalized_sql_metrics ||= definition&.normalized_sql_metrics&.map { |m| { name: m["metric_name"], sql: m["sql"] } } || []
    end

    # Prepends merchant-visible description (app + email) and optional static email-only body.
    def apply_definition_email_prefixes(result)
      chunks_html = []
      chunks_text = []

      desc = definition&.merchant_description.to_s.strip
      if desc.present?
        chunks_html << "<p>#{ERB::Util.html_escape(desc).gsub("\n", "<br>")}</p>"
        chunks_text << "#{desc}\n"
      end

      email_body = definition&.email_body.to_s.strip
      if email_body.present?
        chunks_html << "<p>#{ERB::Util.html_escape(email_body).gsub("\n", "<br>")}</p>"
        chunks_text << "#{email_body}\n"
      end

      return result if chunks_html.empty?

      prefix_text = chunks_text.join("\n\n")
      prefix_text = "#{prefix_text}\n\n" if prefix_text.present?
      Result.new(
        subject: result.subject,
        body_text: prefix_text + result.body_text.to_s,
        body_html: chunks_html.join + result.body_html.to_s,
        attachment_name: result.attachment_name,
        attachment_content: result.attachment_content,
      )
    end

    def delivery_status_ratio
      orders = base_orders.where.not(shipping_status: [nil, ""])
      stats = shipping_stats_from_orders(orders, base_orders)

      lines = []
      lines << "Delivery status ratio — #{@shop.shopify_domain}"
      lines << "Window: order confirmations from #{(30.days.ago).in_time_zone(@report.deliver_timezone).to_date} (last 30 days, shop timezone)."
      terminal = stats[:terminal_total]
      if terminal.positive?
        lines << "Delivered: #{stats[:delivered_count]} (#{stats[:delivered_pct]}%)"
        lines << "Undelivered / RTO: #{stats[:undelivered_count]} (#{stats[:undelivered_pct]}%)"
      else
        lines << "No terminal statuses (delivered/undelivered) in this window."
        lines << "Delivered: #{stats[:delivered_count]}, Undelivered: #{stats[:undelivered_count]}"
      end
      if stats[:other_statuses].any?
        lines << "Other statuses:"
        stats[:other_statuses].each { |k, v| lines << "  #{humanize_status(k)}: #{v}" }
      end
      lines << "Orders without status: #{stats[:missing_status_count]}"

      body_text = lines.join("\n")
      body_html = "<pre>#{ERB::Util.html_escape(body_text)}</pre>"

      if @report.output_format == "csv_attachment"
        csv = CSV.generate do |csv_row|
          csv_row << %w[status count]
          stats[:by_status].each { |k, v| csv_row << [k, v] }
          csv_row << ["_missing_status", stats[:missing_status_count]]
        end
        return Result.new(
          subject: "#{@shop.owner_name} — Delivery status (#{Date.current})",
          body_text: body_text,
          body_html: body_html,
          attachment_name: "delivery-status-#{Date.current}.csv",
          attachment_content: csv,
        )
      end

      Result.new(
        subject: "#{@shop.owner_name} — Delivery status (#{Date.current})",
        body_text: body_text,
        body_html: body_html,
        attachment_name: nil,
        attachment_content: nil,
      )
    end

    def abandoned_cart_messages
      from = 24.hours.ago
      scope = @shop.abandoned_carts.where(created_at: from..)
      total = scope.count
      success = scope.where(status: "SUCCESS").count
      failed = scope.where.not(status: "SUCCESS").count
      recovered = scope.where("LOWER(notes) = ?", "recovered").count
      by_channel = scope.group(:notif_type).count

      lines = []
      lines << "Abandoned cart messages — #{@shop.shopify_domain}"
      lines << "Window: last 24 hours (cutoff #{from.utc.iso8601})."
      lines << "Total sends: #{total}"
      lines << "SUCCESS: #{success}"
      lines << "Other / failed: #{failed}"
      lines << "Converted (recovered): #{recovered}"
      lines << "By channel:"
      by_channel.each { |k, v| lines << "  #{k || 'unknown'}: #{v}" }

      body_text = lines.join("\n")
      body_html = "<pre>#{ERB::Util.html_escape(body_text)}</pre>"

      if @report.output_format == "csv_attachment"
        csv = CSV.generate(headers: true) do |csv_row|
          csv_row << %w[id checkout_id notif_type status notes phone total_price created_at]
          scope.order(created_at: :desc).limit(5000).find_each do |r|
            csv_row << [r.id, r.checkout_id, r.notif_type, r.status, r.notes, r.phone, r.total_price, r.created_at&.iso8601]
          end
        end
        return Result.new(
          subject: "#{@shop.owner_name} — Abandoned cart activity (#{Date.current})",
          body_text: body_text,
          body_html: body_html,
          attachment_name: "abandoned-cart-24h-#{Date.current}.csv",
          attachment_content: csv,
        )
      end

      Result.new(
        subject: "#{@shop.owner_name} — Abandoned cart activity (#{Date.current})",
        body_text: body_text,
        body_html: body_html,
        attachment_name: nil,
        attachment_content: nil,
      )
    end

    def preorder_otp_csv
      from = 24.hours.ago
      scope = @shop.pre_order_otps.otp_sends.where(created_at: from..)
      cnt = scope.count
      tz = @report.deliver_timezone

      csv = CSV.generate(headers: true) do |csv_row|
        csv_row << ["created_at", "phone", "country_code", "status", "order_status", "verification_status", "ver_type", "cart_summary"]
        scope.order(created_at: :desc).limit(5000).find_each do |r|
          csv_row << [
            r.created_at&.in_time_zone(tz)&.strftime("%Y-%m-%d %H:%M %Z"),
            r.phone,
            r.country_code,
            r.status,
            r.order_status,
            r.verification_status,
            r.ver_type,
            format_cart_line(r.cart_details),
          ]
        end
      end

      summary = "Pre-order OTP export — #{@shop.shopify_domain}\nRows: #{cnt}\nWindow: last 24 hours."
      body_html = "<p>#{ERB::Util.html_escape(summary)}</p>"

      Result.new(
        subject: "#{@shop.owner_name} — Pre-order OTP carts 24h (#{Date.current})",
        body_text: summary,
        body_html: body_html,
        attachment_name: "preorder-otp-24h-#{Date.current}.csv",
        attachment_content: csv,
      )
    end

    def multi_sql_report
      metrics = normalized_sql_metrics

      if @report.output_format == "csv_attachment"
        csv = CSV.generate do |csv_row|
          metrics.each do |m|
            csv_row << ["# #{m[:name]}"]
            result = SafeSqlRunner.run!(m[:sql], @shop.id)
            csv_row << result.columns
            result.rows.each { |row| csv_row << row.map { |c| c.is_a?(Time) ? c.iso8601 : c } }
            csv_row << []
          end
        end
        summary = "Custom report: #{@report.name}"
        return Result.new(
          subject: "#{@shop.owner_name} — #{@report.name} (#{Date.current})",
          body_text: summary,
          body_html: "<p>#{ERB::Util.html_escape(summary)}</p>",
          attachment_name: "custom-report-#{definition.id}-#{Date.current}.csv",
          attachment_content: csv,
        )
      end

      html_parts = []
      text_parts = []
      metrics.each do |m|
        result = SafeSqlRunner.run!(m[:sql], @shop.id)
        html_parts << metric_block_html(m[:name], result)
        text_parts << metric_block_text(m[:name], result)
      end

      body_html = html_parts.join
      intro = "<p><strong>#{ERB::Util.html_escape(@report.name)}</strong></p>"
      body_text = ([@report.name.to_s] + text_parts).join("\n\n")

      Result.new(
        subject: "#{@shop.owner_name} — #{@report.name} (#{Date.current})",
        body_text: body_text,
        body_html: intro + body_html,
        attachment_name: nil,
        attachment_content: nil,
      )
    end

    def metric_block_html(metric_name, result)
      cols = result.columns
      table_rows = result.rows.first(100).map do |row|
        cells = row.map { |c| ERB::Util.html_escape(c.is_a?(Time) ? c.iso8601 : c.to_s) }
        "<tr>#{cells.map { |c| "<td>#{c}</td>" }.join}</tr>"
      end
      header = cols.map { |c| ERB::Util.html_escape(c.to_s) }.join("</th><th>")
      <<~HTML
        <h2 style="font-size:17px;margin:24px 0 12px;color:#0f172a;">#{ERB::Util.html_escape(metric_name)}</h2>
        <table><thead><tr><th>#{header}</th></tr></thead>
        <tbody>#{table_rows.join}</tbody></table>
      HTML
    end

    def metric_block_text(metric_name, result)
      cols = result.columns
      lines = [metric_name.to_s, cols.join(", ")]
      result.rows.first(100).each { |row| lines << row.join("\t") }
      lines.join("\n")
    end

    def custom_sql_report
      result = SafeSqlRunner.run!(@report.sql_text, @shop.id)
      cols = result.columns

      if @report.output_format == "csv_attachment"
        csv = CSV.generate do |csv_row|
          csv_row << cols
          result.rows.each { |row| csv_row << row.map { |c| c.is_a?(Time) ? c.iso8601 : c } }
        end
        summary = "Custom report: #{@report.name}\n#{result.rows.size} row(s)."
        return Result.new(
          subject: "#{@shop.owner_name} — #{@report.name} (#{Date.current})",
          body_text: summary,
          body_html: "<p>#{ERB::Util.html_escape(summary)}</p>",
          attachment_name: "custom-report-#{definition.id}-#{Date.current}.csv",
          attachment_content: csv,
        )
      end

      table_rows = result.rows.first(100).map do |row|
        cells = row.map { |c| ERB::Util.html_escape(c.is_a?(Time) ? c.iso8601 : c.to_s) }
        "<tr>#{cells.map { |c| "<td>#{c}</td>" }.join}</tr>"
      end
      header = cols.map { |c| ERB::Util.html_escape(c.to_s) }.join("</th><th>")
      body_html = <<~HTML
        <p><strong>#{ERB::Util.html_escape(@report.name)}</strong></p>
        <table><thead><tr><th>#{header}</th></tr></thead>
        <tbody>#{table_rows.join}</tbody></table>
      HTML
      plain_lines = [@report.name.to_s]
      plain_lines << cols.join(", ")
      result.rows.first(100).each { |row| plain_lines << row.join("\t") }

      Result.new(
        subject: "#{@shop.owner_name} — #{@report.name} (#{Date.current})",
        body_text: plain_lines.join("\n"),
        body_html: body_html,
        attachment_name: nil,
        attachment_content: nil,
      )
    end

    def base_orders
      @shop.order_confirmations
        .where(created_at: 30.days.ago.beginning_of_day..Time.current.end_of_day)
        .where.not(status: "Test-Order")
    end

    def shipping_stats_from_orders(with_status_scope, all_orders_scope)
      rows = with_status_scope.pluck(:shipping_status, :is_cod_order)
      by_status = Hash.new(0)
      rows.each do |status, _is_cod|
        key = status.to_s.strip.downcase
        next if key.blank?

        by_status[key] += 1
      end

      delivered = by_status["delivered"] || 0

      # Treat these as terminal "undelivered / RTO" outcomes.
      # (Requested: mark, failure, undelivered, restock)
      undelivered_keys = %w[
        undelivered
        failure
        failed
        restock
        restocked
      ].freeze

      undelivered = undelivered_keys.sum { |k| by_status[k] || 0 }
      terminal_total = delivered + undelivered
      other = by_status.except("delivered", *undelivered_keys)

      {
        delivered_count: delivered,
        undelivered_count: undelivered,
        terminal_total: terminal_total,
        delivered_pct: terminal_total.positive? ? ((delivered.to_f / terminal_total) * 100).round(1) : 0,
        undelivered_pct: terminal_total.positive? ? ((undelivered.to_f / terminal_total) * 100).round(1) : 0,
        by_status: by_status.sort_by { |_, v| -v }.to_h,
        other_statuses: other.sort_by { |_, v| -v }.to_h,
        missing_status_count: all_orders_scope.where(shipping_status: [nil, ""]).count,
      }
    end

    def humanize_status(key)
      key.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
    end

    def format_cart_line(raw)
      return "" if raw.blank?

      details =
        if raw.is_a?(Array)
          if raw.first.is_a?(Hash)
            raw
          else
            []
          end
        else
          []
        end

      details.map do |item|
        next unless item.is_a?(Hash)

        title = item["title"].to_s
        qty = item["quantity"].to_s.presence || "1"
        "#{qty} x #{title}"
      end.compact.join("; ")
    rescue StandardError
      ""
    end
  end
end
