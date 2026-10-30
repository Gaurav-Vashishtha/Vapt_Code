# frozen_string_literal: true

module CustomBranded
  # GET /cb/:shop_domain/templates/:id/activity — recent sends of one template
  #   (API calls, portal tests, event-driven sends) for the template drawer.
  # GET /cb/:shop_domain/activity — every send for the brand, for the portal's
  #   Activity card. Filters: status, template (name), to; before_id cursor.
  # Session-gated like the rest of the portal, so no API token is needed.
  class TemplateActivitiesController < BaseController
    SOURCE_LABELS = {
      'custom_branded_api' => 'API',
      'custom_branded_test' => 'Portal test'
    }.freeze

    def index
      template = @client.whatsapp_templates.find_by(id: params[:id])
      return render json: { error: 'template not found' }, status: :not_found unless template

      limit = params[:limit].to_i.clamp(1, 50)
      limit = 20 if params[:limit].blank?
      logs = @client.whatsapp_message_logs.where(whatsapp_template_id: template.id).recent.limit(limit)

      render json: { activities: logs.map { |log| serialize(log) } }
    end

    PAGE_SIZE = 25
    SUMMARY_WINDOW = 7.days

    def brand
      scope = @client.whatsapp_message_logs.recent
      if params[:status].present? && WhatsappMessageLog.statuses.key?(params[:status])
        scope = scope.where(status: params[:status])
      end
      scope = scope.where(template_name: params[:template].to_s) if params[:template].present?
      if params[:to].present?
        digits = params[:to].to_s.gsub(/\D/, '')
        scope = scope.where('recipient LIKE ?', "%#{WhatsappMessageLog.sanitize_sql_like(digits)}%") if digits.present?
      end
      scope = scope.where('id < ?', params[:before_id].to_i) if params[:before_id].present?

      logs = scope.limit(PAGE_SIZE).to_a
      render json: {
        activities: logs.map { |log| serialize(log) },
        next_before_id: (logs.last.id if logs.size == PAGE_SIZE),
        summary: summary
      }
    end

    private

    def summary
      counts = @client.whatsapp_message_logs
                      .where(created_at: SUMMARY_WINDOW.ago..)
                      .group(:status).count
      totals = WhatsappMessageLog.statuses.keys.index_with { |s| counts[s].to_i }
      totals.merge('total' => totals.values.sum, 'days' => SUMMARY_WINDOW.in_days.to_i)
    end

    def serialize(log)
      snapshot = log.payload_snapshot.is_a?(Hash) ? log.payload_snapshot : {}
      {
        id: log.id,
        status: log.status,
        template: log.template_name,
        source: SOURCE_LABELS.fetch(log.event_type_key, log.event_type_key.to_s.humanize),
        recipient: log.recipient,
        idempotency_key: log.source_external_id,
        variables: snapshot['variables'],
        error_code: log.error_code,
        error_message: log.error_message,
        created_at: log.created_at&.iso8601,
        sent_at: log.sent_at&.iso8601,
        delivered_at: log.delivered_at&.iso8601,
        read_at: log.read_at&.iso8601,
        failed_at: log.failed_at&.iso8601
      }
    end
  end
end
