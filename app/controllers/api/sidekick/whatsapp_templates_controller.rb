# frozen_string_literal: true

module Api
  module Sidekick
    # Approval state of templates on the merchant's own WhatsApp number.
    # Rejected / paused templates are the common reason branded messages stop.
    class WhatsappTemplatesController < BaseController
      def index
        templates = @shop.whatsapp_templates.order(updated_at: :desc)
        templates = templates.where(status: params[:status]) if WhatsappTemplate.statuses.key?(params[:status].to_s)

        counts = @shop.whatsapp_templates.group(:status).count

        render json: {
          summary: { total: counts.values.sum, by_status: counts },
          results: templates.limit(result_limit).map { |t| template_link(t) }
        }
      end

      private

      def template_link(template)
        resource_link(
          type: 'whatsapp_template',
          id: template.id,
          name: "#{template.name} (#{template.language}) — #{template.status}",
          meta: {
            status: template.status,
            category: template.category,
            used_for: template.event_type_key.presence,
            rejection_reason: (template.rejection_reason unless template.rejection_reason.to_s.casecmp?('none')).presence,
            last_synced_at: template.last_synced_at&.iso8601
          }
        )
      end
    end
  end
end
