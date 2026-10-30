# frozen_string_literal: true

module CustomBranded
  class EventTemplateMapper
    class Invalid < StandardError; end

    def self.call(client:, template:, attrs:)
      new(client, template, attrs).call
    end

    def initialize(client, template, attrs)
      @client = client
      @template = template
      @attrs = (attrs.respond_to?(:to_unsafe_h) ? attrs.to_unsafe_h : attrs.to_h).with_indifferent_access
    end

    def call
      event = ParcelxEventCatalog.find(attrs[:event_id], client: client)
      raise Invalid, 'Choose the ParcelX event this template is for.' if event.nil?

      if self.class.header_variable?(template)
        raise Invalid, 'This template has a variable in its header, which event messages cannot fill. Create a new template with a fixed header instead.'
      end

      allowed = event['variables'].index_by { |v| v['key'] }
      keys = Array(attrs[:variables]).map(&:to_s)
      expected = self.class.placeholder_count(template)
      if keys.size != expected || keys.any?(&:blank?)
        raise Invalid, "This template has #{expected} placeholder(s) — pick a variable for each one."
      end

      button_variables = (attrs[:button_variables].is_a?(Hash) ? attrs[:button_variables] : {})
                         .to_h.transform_keys(&:to_s).transform_values(&:to_s).reject { |_, v| v.blank? }
      dynamic = self.class.dynamic_url_button_indices(template).map(&:to_s)
      unknown_buttons = button_variables.keys - dynamic
      raise Invalid, "Button #{unknown_buttons.first} has no dynamic link to fill." if unknown_buttons.any?

      unknown = (keys + button_variables.values).reject { |k| allowed.key?(k) }
      raise Invalid, "#{unknown.first} is not a variable of the “#{event['event_name']}” event." if unknown.any?

      mapping = CustomBrandedTemplateEvent.find_or_initialize_by(whatsapp_template_id: template.id)
      event_changed = mapping.persisted? && mapping.event_id != event['event_id']
      mapping.assign_attributes(
        custom_branded_client: client,
        event_id: event['event_id'],
        event_name: event['event_name'],
        event_group: event['group'],
        variables: keys.map { |k| allowed[k].slice('key', 'label', 'sample') },
        button_variables: button_variables
      )
      fresh = mapping.new_record? || event_changed
      mapping.active = false if fresh
      mapping.save!
      mapping.activate! if fresh && !mapping.siblings.active.exists?
      mapping
    end

    def self.header_variable?(template)
      header = Array(template.components).find { |c| c.is_a?(Hash) && c['type'].to_s.casecmp?('HEADER') }
      header.present? && header['format'].to_s.casecmp?('TEXT') && header['text'].to_s.include?('{{')
    end

    def self.placeholder_count(template)
      body = Array(template.components).find { |c| c.is_a?(Hash) && c['type'].to_s.casecmp?('BODY') }
      body&.dig('text').to_s.scan(/\{\{(\d+)\}\}/).flatten.map(&:to_i).max.to_i
    end

    def self.dynamic_url_button_indices(template)
      buttons = Array(template.components).find { |c| c.is_a?(Hash) && c['type'].to_s.casecmp?('BUTTONS') }
      Array(buttons&.dig('buttons')).each_with_index.filter_map do |b, i|
        next unless b.is_a?(Hash) && b['type'].to_s.casecmp?('URL')

        i if b['url'].to_s.include?('{{') || b['example'].present?
      end
    end

    private

    attr_reader :client, :template, :attrs
  end
end
