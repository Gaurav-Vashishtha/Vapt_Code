# frozen_string_literal: true

module CustomBranded
  class EventTemplateBuilder
    class Invalid < StandardError; end

    TOKEN = /\{\{\s*([A-Za-z0-9_.]+)\s*\}\}/
    BODY_LIMIT = 1024
    SHORT_TEXT_LIMIT = 60
    BUTTON_TEXT_LIMIT = 25
    MAX_BUTTONS = 3
    CATEGORIES = %w[UTILITY MARKETING].freeze

    def self.call(client:, account:, attrs:)
      new(client, account, attrs).call
    end

    def initialize(client, account, attrs)
      @client = client
      @account = account
      @attrs = (attrs.respond_to?(:to_unsafe_h) ? attrs.to_unsafe_h : attrs.to_h).with_indifferent_access
      @button_variables = {}
    end

    def call
      @event = ParcelxEventCatalog.find(attrs[:event_id], client: client)
      raise Invalid, 'Choose the ParcelX event this template is for.' if @event.nil?

      @allowed = @event['variables'].index_by { |v| v['key'] }
      body_component, variables = build_body
      components = [build_header, body_component, build_footer, build_buttons].compact

      template = ::Meta::TemplateService.call(
        account: account,
        operation: :create,
        attrs: { name: template_name, language: language, category: category, components: components }
      )

      mapping = CustomBrandedTemplateEvent.find_or_initialize_by(whatsapp_template_id: template.id)
      mapping.assign_attributes(
        custom_branded_client: client,
        event_id: @event['event_id'],
        event_name: @event['event_name'],
        event_group: @event['group'],
        variables: variables,
        button_variables: @button_variables,
        active: false
      )
      mapping.save!
      activate(mapping) if activate?(mapping)
      template.reload
    end

    private

    attr_reader :client, :account, :attrs

    def template_name
      name = attrs[:name].to_s.strip
      raise Invalid, 'Template name can only use lowercase letters, numbers and underscores.' unless name.match?(/\A[a-z0-9_]{1,512}\z/)

      name
    end

    def language
      attrs[:language].presence || 'en'
    end

    def category
      value = attrs[:category].to_s.upcase
      CATEGORIES.include?(value) ? value : 'UTILITY'
    end

    def activate?(mapping)
      requested = attrs[:activate]
      return ActiveModel::Type::Boolean.new.cast(requested) unless requested.nil?

      !mapping.siblings.active.exists?
    end

    # The template already exists on Meta at this point, so a lost activation race must not fail
    # the request: a retry would hit "template name already exists". It stays inactive instead.
    def activate(mapping)
      mapping.activate!
    rescue ActiveRecord::RecordNotUnique
      mapping.reload
    end

    def variable!(key)
      @allowed[key] || raise(Invalid, "{{#{key}}} is not a variable of the “#{@event['event_name']}” event. Insert variables from the list.")
    end

    def build_body
      text = attrs[:body].to_s.strip
      raise Invalid, 'Write the message body.' if text.blank?

      order = []
      compiled = text.gsub(TOKEN) do
        key = Regexp.last_match(1)
        variable!(key)
        order << key unless order.include?(key)
        "{{#{order.index(key) + 1}}}"
      end
      raise Invalid, "The message body is #{compiled.length} characters; WhatsApp allows #{BODY_LIMIT}." if compiled.length > BODY_LIMIT

      variables = order.map { |key| @allowed[key].slice('key', 'label', 'sample') }
      component = { 'type' => 'BODY', 'text' => compiled }
      component['example'] = { 'body_text' => [variables.map { |v| example_for(v) }] } if variables.any?
      [component, variables]
    end

    def example_for(variable)
      variable['sample'].presence || variable['label']
    end

    def build_header
      header = attrs[:header].is_a?(Hash) ? attrs[:header] : {}
      case header[:type].to_s
      when 'text'
        text = header[:text].to_s.strip
        return nil if text.blank?
        raise Invalid, 'The header cannot contain variables.' if text.include?('{{')
        raise Invalid, "The header can be at most #{SHORT_TEXT_LIMIT} characters." if text.length > SHORT_TEXT_LIMIT

        { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => text }
      when 'image'
        url = header[:image_url].to_s.strip
        raise Invalid, 'The header image must be a public https:// link to a JPG or PNG.' unless url.start_with?('https://')

        { 'type' => 'HEADER', 'format' => 'IMAGE', 'example' => { 'header_handle' => [url] } }
      end
    end

    def build_footer
      text = attrs[:footer].to_s.strip
      return nil if text.blank?
      raise Invalid, 'The footer cannot contain variables.' if text.include?('{{')
      raise Invalid, "The footer can be at most #{SHORT_TEXT_LIMIT} characters." if text.length > SHORT_TEXT_LIMIT

      { 'type' => 'FOOTER', 'text' => text }
    end

    def build_buttons
      raw = Array(attrs[:buttons]).select { |b| b.is_a?(Hash) }
      return nil if raw.empty?
      raise Invalid, "A template can have at most #{MAX_BUTTONS} buttons." if raw.size > MAX_BUTTONS

      buttons = raw.each_with_index.map { |button, index| build_button(button.with_indifferent_access, index) }
      { 'type' => 'BUTTONS', 'buttons' => buttons }
    end

    def build_button(button, index)
      text = button[:text].to_s.strip
      raise Invalid, 'Every button needs a label.' if text.blank?
      raise Invalid, "Button labels can be at most #{BUTTON_TEXT_LIMIT} characters." if text.length > BUTTON_TEXT_LIMIT

      return { 'type' => 'QUICK_REPLY', 'text' => text } unless button[:type].to_s == 'url'

      url = button[:url].to_s.strip
      raise Invalid, "The “#{text}” button needs a link starting with https://." unless url.start_with?('https://')
      raise Invalid, "Type the fixed part of the “#{text}” link only, then pick the variable to append." if url.include?('{{')

      key = button[:variable].presence
      return { 'type' => 'URL', 'text' => text, 'url' => url } if key.nil?

      variable = variable!(key)
      @button_variables[index.to_s] = key
      { 'type' => 'URL', 'text' => text, 'url' => "#{url}{{1}}", 'example' => ["#{url}#{example_for(variable)}"] }
    end
  end
end
