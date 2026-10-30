# frozen_string_literal: true

module Api
  module Whatsapp
    module Inbox
      class TemplatesController < BaseController
        MAX_TEMPLATES = 200
        PREFILL_SOURCES = {
          'customer.first' => 'first_name',
          'customer.name' => 'name',
          'recipient.name' => 'name',
          'store.name' => 'store_name',
          'order.id' => 'order_number',
          'order.total' => 'order_amount',
          'order.status_url' => 'tracking_url',
          'tracking.url' => 'tracking_url'
        }.freeze

        before_action :load_conversation

        def index
          variables = template_variables
          opted_out = ::Whatsapp::Inbox::TemplateSender.customer_opted_out?(@conversation)
          templates = inbox_templates(@conversation)
                      .order(:name, :language, :id)
                      .limit(MAX_TEMPLATES)
                      .select { |t| inbox_template_pickable?(t) && !(opted_out && t.marketing?) }
          render json: { templates: templates.map { |t| serialize(t, variables) } }
        end

        private

        def serialize(template, variables)
          body = ::Whatsapp::TemplateComponents.text_of(template.components, 'BODY')
          placeholders = ::Whatsapp::TemplateComponents.placeholders(body).uniq.map(&:to_s)
          {
            id: template.id,
            name: template.name,
            language: template.language,
            category: template.read_attribute_before_type_cast('category'),
            body_text: body,
            placeholders: placeholders,
            header_type: inbox_template_header_type(template),
            prefill: prefill(template, placeholders, variables)
          }
        end

        def prefill(template, placeholders, variables)
          mapping = template.variable_mapping.is_a?(Hash) ? template.variable_mapping : {}
          placeholders.each_with_object({}) do |position, out|
            value = variables[PREFILL_SOURCES[mapping[position].to_s]].to_s
            out[position] = value if value.present?
          end
        end

        def template_variables
          ::Whatsapp::Inbox::ReplyVariables.values_for(@conversation)
        rescue StandardError => e
          Rails.logger.error("[api/whatsapp/inbox/templates] variables conv=#{@conversation.id} #{e.class}: #{e.message}")
          {}
        end
      end
    end
  end
end
