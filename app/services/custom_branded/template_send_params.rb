# frozen_string_literal: true

module CustomBranded
  # Turns a caller-supplied set of values into the Meta component parameters
  # a template send needs, validating everything that can be checked before
  # the HTTP call. Shared by the partner API (POST /api/v1/cb/messages) and
  # the portal's "test this template" action so both accept the same input
  # shape and reject the same things.
  #
  # Input (a Hash / ActionController::Parameters):
  #   variables:      {"1" => "..", "2" => ".."} or ["..", ".."]   (body {{n}})
  #   header_text:    value for a TEXT header carrying {{1}}
  #   header_image_url / header_video_url / header_document_url
  #   button_param:   value applied to EVERY dynamic URL button
  #   button_params:  {"<index>" => value} per dynamic URL button (wins)
  #
  # Result: #ok?, #error, #detail, #body_parameters, #header_parameters,
  #         #url_button_params, #quick_reply_button_params, #raw_variables
  class TemplateSendParams
    Result = Struct.new(:error, :detail, :body_parameters, :header_parameters,
                        :url_button_params, :quick_reply_button_params, :raw_variables,
                        keyword_init: true) do
      def ok? = error.nil?
    end

    def self.call(template:, params:)
      new(template, params).call
    end

    def initialize(template, params)
      @template = template
      @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : (params || {})
      @params = @params.with_indifferent_access
    end

    def call
      body = build_body_parameters
      return failure(@variables_error, @variables_detail) if @variables_error

      header = build_header_parameters
      return failure(@header_error) if @header_error

      url_buttons = resolve_url_button_params
      return failure('button_param_required', @button_error) if @button_error

      Result.new(
        body_parameters: body,
        header_parameters: header,
        url_button_params: url_buttons,
        quick_reply_button_params: quick_reply_button_params,
        raw_variables: raw_variables
      )
    end

    private

    attr_reader :template, :params

    def failure(error, detail = nil)
      Result.new(error: error, detail: detail)
    end

    def raw_variables
      params[:variables].as_json
    end

    def component(type)
      Array(template.components).find { |c| c.is_a?(Hash) && c['type'].to_s.casecmp?(type) }
    end

    def build_body_parameters
      body_text = component('BODY')&.dig('text').to_s
      expected = body_text.scan(/\{\{(\d+)\}\}/).flatten.map(&:to_i).max.to_i

      values = named_variables? ? named_body_values(expected) : positional_body_values
      return nil if @variables_error

      if values.size < expected
        @variables_error = "template expects #{expected} variable(s), got #{values.size}"
        return nil
      end

      values.first(expected).map { |t| { 'type' => 'text', 'text' => t } }
    end

    def positional_body_values
      if (named = raw_variables).is_a?(Hash) && named.keys.any? { |k| !k.to_s.match?(/\A\d+\z/) }
        @variables_error = 'template_not_mapped'
        @variables_detail = "Template #{template.id} is not mapped to an event, so variables must be keyed by position ({\"1\": \"...\"}) or sent as an array."
        return []
      end

      values =
        case (v = raw_variables)
        when Hash  then v.sort_by { |k, _| k.to_s.to_i }.map(&:last)
        when Array then v
        else []
        end
      values.map(&:to_s)
    end

    def event_mapping
      return @event_mapping if defined?(@event_mapping)

      @event_mapping = template.custom_branded_template_event
    end

    def named_variables?
      vars = raw_variables
      event_mapping.present? && vars.is_a?(Hash) && vars.keys.any? { |k| !k.to_s.match?(/\A\d+\z/) }
    end

    def named_body_values(expected)
      keys = event_mapping.variable_keys
      if keys.size != expected
        @variables_error = 'template_mapping_outdated'
        @variables_detail = "The template now has #{expected} placeholder(s) but its event mapping covers #{keys.size}. Re-map it on the portal."
        return []
      end

      missing = event_mapping.required_variable_keys.select { |k| named_value(k).nil? }
      if missing.any?
        @variables_error = 'missing_variables'
        @variables_detail = "Template #{template.id} is mapped to event #{event_mapping.event_id} (#{event_mapping.event_name}) and needs: #{event_mapping.required_variable_keys.join(', ')}. Missing or empty: #{missing.join(', ')}."
        return []
      end

      keys.map { |k| named_value(k) }
    end

    def named_value(key)
      vars = raw_variables
      value = vars[key]
      value = dig_path(vars, key) if value.nil?
      return nil if value.is_a?(Hash) || value.is_a?(Array)

      # Meta rejects text parameters containing newlines, tabs or 4+ consecutive spaces (#132018).
      text = value.to_s.gsub(/[\r\n\t]+/, ' ').gsub(/ {4,}/, '   ').strip
      text.empty? ? nil : text
    end

    def dig_path(node, key)
      key.to_s.split('.').reduce(node) do |current, segment|
        case current
        when Hash then current[segment]
        when Array then segment.match?(/\A\d+\z/) ? current[segment.to_i] : nil
        end
      end
    end

    def mapped_button_value(index)
      return nil unless named_variables?

      key = event_mapping.button_variables.to_h[index.to_s]
      key.present? ? named_value(key) : nil
    end

    def template_buttons
      Array(component('BUTTONS')&.dig('buttons'))
    end

    def dynamic_url_button_indices
      template_buttons.each_with_index.filter_map do |b, i|
        next unless b.is_a?(Hash) && b['type'].to_s.casecmp?('URL')
        next unless b['url'].to_s.include?('{{') || b['example'].present?

        i
      end
    end

    def resolve_url_button_params
      indices = dynamic_url_button_indices
      return nil if indices.empty?

      per_index = params[:button_params]
      per_index = {} unless per_index.is_a?(Hash)

      indices.map do |i|
        value = per_index[i.to_s].presence || params[:button_param].presence || mapped_button_value(i)
        if value.blank?
          @button_error = "This template has #{indices.size} URL button(s) with a dynamic {{n}} placeholder (at index #{indices.join(', ')}) — pass button_param (applied to all) or button_params (per index, e.g. {\"#{indices.first}\": \"value\"})."
          return nil
        end
        { 'index' => i, 'param' => value.to_s }
      end
    end

    def quick_reply_button_params
      out = template_buttons.each_with_index.filter_map do |b, i|
        next unless b.is_a?(Hash) && b['type'].to_s.casecmp?('QUICK_REPLY')

        { 'index' => i, 'payload' => b['text'].to_s }
      end
      out.presence
    end

    def build_header_parameters
      header = component('HEADER')
      format = header&.dig('format').to_s.upcase

      if format == 'TEXT'
        return nil unless header['text'].to_s.include?('{{')

        value = params[:header_text].presence
        unless value
          @header_error = 'template has a text header with a {{n}} variable — pass header_text'
          return nil
        end
        return [{ 'type' => 'text', 'text' => value.to_s }]
      end

      return nil unless %w[IMAGE VIDEO DOCUMENT].include?(format)

      kind = format.downcase
      explicit = params[:"header_#{kind}_url"].presence
      return [{ 'type' => kind, kind => { 'link' => explicit } }] if explicit

      param = template.media_header_param(nil, nil)
      return [param] if param

      @header_error = "template has a #{format} header — pass header_#{kind}_url"
      nil
    end
  end
end
