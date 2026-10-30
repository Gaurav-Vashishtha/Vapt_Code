module Api
  module Whatsapp
    class MessageLogsController < AuthenticatedController
      PER_PAGE_DEFAULT = 50
      PER_PAGE_MAX = 200

      def index
        per = [params[:per_page].to_i, PER_PAGE_DEFAULT].max
        per = [per, PER_PAGE_MAX].min
        page = [params[:page].to_i, 1].max

        scope = @shop.whatsapp_message_logs
                     .recent
                     .for_event(params[:event_type_key])
                     .with_status(params[:status])

        scope = scope.where(whatsapp_campaign_id: params[:campaign_id]) if params[:campaign_id].present?
        if params[:q].present?
          scope = scope.where('recipient ILIKE :q OR meta_message_id ILIKE :q', q: "%#{params[:q].to_s.strip}%")
        end

        # Optional `days` window (1/3/7/30/90). Filtered on created_at — the
        # row's birth time, not its terminal-status time — so the count we
        # show as "Total" matches what's listed.
        days = params[:days].to_i
        if days > 0
          scope = scope.where('created_at >= ?', days.days.ago)
        end

        # `summary=1`: counts only, no rows — used by the WhatsApp hub's
        # 7-day stats and per-notification "sent this week" numbers.
        if params[:summary].present?
          counts = scope.reorder(nil)
          return render json: {
            total: counts.count,
            stats: counts.group(:status).count,
            by_event: counts.group(:event_type_key).count
          }
        end

        logs = scope.offset((page - 1) * per).limit(per).includes(:inbound_messages)

        render json: {
          logs: logs.map { |l| serialize(l) },
          page: page,
          per_page: per,
          total: scope.count,
          # Single GROUP BY query → one trip to the DB for the summary tiles.
          # Counts honour the same date / event / status filters as the table.
          # reorder(nil) strips `.recent`'s ORDER BY created_at so Postgres
          # doesn't complain about created_at not being in the GROUP BY.
          stats: scope.reorder(nil).group(:status).count
        }
      end

      # POST /api/whatsapp/message_logs/:id/retry — re-send the same message.
      # Creates a fresh log row (linked via retry_of_log_id) and returns it so
      # the page can show the new attempt without a full refetch.
      def retry
        log = @shop.whatsapp_message_logs.find_by(id: params[:id])
        return render(json: { error: 'log not found' }, status: :not_found) unless log

        new_log = ::Whatsapp::ResendMessageLogService.call(log: log, shop: @shop)
        render json: { log: serialize(new_log.reload) }, status: :created
      rescue ::Whatsapp::ResendMessageLogService::Error => e
        # A Meta rejection still leaves a :failed row behind — surface it so the
        # merchant sees the new attempt and its error, not just a toast.
        failed = @shop.whatsapp_message_logs.recent.find_by("payload_snapshot->>'retry_of_log_id' = ?", params[:id].to_s)
        render json: { error: e.message, log: (failed ? serialize(failed) : nil) }, status: :unprocessable_entity
      end

      private

      def serialize(l)
        replies = l.inbound_messages.sort_by(&:received_at).reverse.first(5)
        snap = l.payload_snapshot.is_a?(Hash) ? l.payload_snapshot : {}
        {
          id: l.id,
          retry_of_log_id: snap['retry_of_log_id'],
          retry_attempt: snap['retry_attempt'],
          event_type_key: l.event_type_key,
          template_name: l.template_name,
          template_language: l.whatsapp_template&.language,
          template_components: l.whatsapp_template&.components,
          recipient: l.recipient,
          status: l.status,
          meta_message_id: l.meta_message_id,
          error_code: l.error_code,
          error_message: l.error_message,
          sent_at: l.sent_at,
          delivered_at: l.delivered_at,
          read_at: l.read_at,
          failed_at: l.failed_at,
          created_at: l.created_at,
          # Customer replies tied to this outbound (quick-reply taps and
          # interactive replies). Most-recent-first, capped at 5 — the row
          # detail pane can fetch more if we ever need it.
          replies: replies.map { |r|
            {
              id: r.id,
              kind: r.kind,
              payload: r.payload,
              display_text: r.display_text,
              received_at: r.received_at
            }
          },
          reply_count: l.inbound_messages.size,
          # Only the bits the preview pane needs — full payload can be heavy
          # for a Shopify order.
          # - `used_samples` is what TestMessageService stores (legacy).
          # - `body_parameters` is the resolved Meta-shape array of {type, text}
          #   stored by SendTemplateMessageService — the values actually sent.
          used_samples: l.payload_snapshot.is_a?(Hash) ? l.payload_snapshot['used_samples'] : nil,
          body_parameters: l.payload_snapshot.is_a?(Hash) ? l.payload_snapshot['body_parameters'] : nil,
          diagnostics: diagnostics_for(l, snap)
        }
      end

      # "What was sent" panel in the Message detail modal: the exact header /
      # button parameters, which number and template sent it, and what the
      # order payload looked like — enough to debug a Meta rejection from the UI.
      def diagnostics_for(l, snap)
        tpl = l.whatsapp_template
        acc = l.whatsapp_account
        order = snap['order'].is_a?(Hash) ? snap['order'] : nil
        line_items = order && order['line_items']
        {
          send_request: snap['send_request'],
          meta_attempts: snap['meta_attempts'],
          sending_account_id: l.whatsapp_account_id,
          sending_phone: acc&.display_phone_number,
          template_id: tpl&.id,
          template_account_id: tpl&.whatsapp_account_id,
          template_status: tpl&.status,
          variable_mapping: tpl&.variable_mapping,
          header_media: tpl&.header_media,
          source_external_id: l.source_external_id,
          payload_keys: snap.keys - %w[body_parameters send_request meta_attempts],
          order_name: order && order['name'],
          line_items: order.nil? ? nil : (line_items.nil? ? 'missing' : Array(line_items).map { |li| li.is_a?(Hash) ? li.slice('title', 'variant_title', 'quantity', 'product_id') : li })
        }
      rescue StandardError => e
        { error: "#{e.class}: #{e.message}" }
      end
    end
  end
end
