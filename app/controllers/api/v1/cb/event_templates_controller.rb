# frozen_string_literal: true

module Api
  module V1
    module Cb
      class EventTemplatesController < BaseController
        def index
          scope = client.custom_branded_template_events
                        .includes(whatsapp_template: :whatsapp_account)
                        .order(:event_id, active: :desc, id: :asc)
          scope = scope.for_event(params[:event_id]) if params[:event_id].present?
          scope = scope.active if ActiveModel::Type::Boolean.new.cast(params[:active])

          render json: { event_templates: scope.filter_map { |m| serialize(m) } }
        end

        private

        def serialize(mapping)
          template = mapping.whatsapp_template
          return nil if template.nil?

          {
            template_id: template.id,
            template_name: template.name,
            language: template.language,
            status: template.status,
            approved: template.approved?,
            account_id: template.whatsapp_account_id
          }.merge(::CustomBranded::EventTemplateSerializer.call(template).except(:sample_request))
        end
      end
    end
  end
end
