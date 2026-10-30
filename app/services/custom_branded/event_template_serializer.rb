# frozen_string_literal: true

module CustomBranded
  module EventTemplateSerializer
    module_function

    def call(template)
      mapping = template.custom_branded_template_event
      return nil if mapping.nil?

      variables = Array(mapping.variables).each_with_index.map do |v, i|
        { position: i + 1, key: v['key'], label: v['label'], sample: v['sample'] }
      end
      samples = Array(mapping.variables).to_h { |v| [v['key'], v['sample']] }

      {
        event_id: mapping.event_id,
        event_name: mapping.event_name,
        event_group: mapping.event_group,
        active: mapping.active,
        live: mapping.live?,
        variables: variables,
        button_variables: mapping.button_variables,
        required_variables: mapping.required_variable_keys,
        sample_request: {
          template_id: template.id,
          to: '919876501234',
          variables: mapping.required_variable_keys.to_h { |k| [k, samples[k].presence || '…'] },
          idempotency_key: "<px_order_id>-#{mapping.event_id}"
        }
      }
    end
  end
end
