module Meta
  class TestMessageService < ApplicationService
    class Error < StandardError; end

    def initialize(account:, to:, template_name:, language: 'en_US', components: nil)
      @account = account
      @to = to
      @template_name = template_name
      @language = language
      @components = components
    end

    def call
      raise Error, 'account is not ready to send' unless account.ready_to_send?
      raise Error, 'recipient phone number is required' if to.blank?
      raise Error, 'template_name is required' if template_name.blank?

      template = account.whatsapp_templates.find_by(name: template_name, language: language)
      raise Error, "template '#{template_name}' (#{language}) not found locally — sync first" unless template

      body_params = components_body_params(components) || sample_body_params(template)
      header_params = sample_header_params(template)

      # If the template has a dynamic URL button (any URL component whose URL
      # contains a {{N}} placeholder — whether registered via our form or
      # created on Meta's side and synced down), Meta requires a value for
      # that {{N}} or returns 131008. Use a stable placeholder slug.
      button_slug = needs_button_param?(template) ? 'test_slug' : nil

      log = Meta::SendTemplateMessageService.call(
        account: account,
        template: template,
        recipient: to,
        body_parameters: body_params,
        header_parameters: header_params,
        event_type_key: 'test_message',
        payload_snapshot: { test: true, used_samples: body_params&.map { |p| p[:text] || p['text'] } },
        button_slug: button_slug
      )

      { ok: true, message_id: log.meta_message_id, recipient: log.recipient }
    rescue Meta::SendTemplateMessageService::Error => e
      raise Error, e.message
    end

    private

    attr_reader :account, :to, :template_name, :language, :components

    # If the caller passed Meta-style components, extract the body parameters
    # so SendTemplateMessageService can repackage them in its own envelope.
    def components_body_params(comps)
      return nil if comps.blank?
      body = Array(comps).find { |c| (c[:type] || c['type']).to_s.casecmp?('body') }
      body && (body[:parameters] || body['parameters'])
    end

    # Build body parameters for a test send. Prefers the template's
    # variable_mapping (which uses EventRegistry samples), and falls back to
    # parsing actual {{N}} placeholders out of the body text — so templates
    # synced from Meta (no mapping) still produce the correct param count and
    # don't trigger Meta's 132000 ("count does not match") error.
    def sample_body_params(template)
      from_mapping = body_params_from_mapping(template)
      return from_mapping if from_mapping

      slots = placeholder_slots(component_text(template, 'BODY'))
      return nil if slots.empty?
      slots.map { |n| { type: 'text', text: "value_#{n}" } }
    end

    # Headers come in four flavours: TEXT (may have {{N}} slots), IMAGE, VIDEO,
    # and DOCUMENT. The latter three always require a media parameter at send
    # time — Meta returns 132012 if missing.
    def sample_header_params(template)
      header = Array(template.components).find do |c|
        c.is_a?(Hash) && c['type'].to_s.casecmp?('HEADER')
      end
      return nil unless header

      case header['format'].to_s.upcase
      when 'TEXT'
        slots = placeholder_slots(header['text'].to_s)
        return nil if slots.empty?
        slots.map { |n| { type: 'text', text: "header_#{n}" } }
      when 'IMAGE'    then [media_header_param('image',    template, header, FALLBACK_IMAGE_URL)]
      when 'VIDEO'    then [media_header_param('video',    template, header, FALLBACK_VIDEO_URL)]
      when 'DOCUMENT' then [media_header_param('document', template, header, FALLBACK_DOCUMENT_URL)]
      end
    end

    # Stable public URLs Meta can fetch at delivery time. placeholder.com and
    # similar tend to be rate-limited or flaky from Meta's IPs and result in
    # accepted-but-undelivered messages.
    FALLBACK_IMAGE_URL    = 'https://picsum.photos/600/400.jpg'.freeze
    FALLBACK_VIDEO_URL    = 'https://download.samplelib.com/mp4/sample-5s.mp4'.freeze
    FALLBACK_DOCUMENT_URL = 'https://www.africau.edu/images/default/sample.pdf'.freeze

    # Wraps WhatsappTemplate#media_header_param and falls back to a public
    # placeholder URL when the template has no resolvable media — keeps test
    # sends from failing on templates that haven't been backfilled yet.
    def media_header_param(kind, template, _header, fallback_url)
      template.media_header_param || { 'type' => kind, kind => { 'link' => fallback_url } }
    end

    def body_params_from_mapping(template)
      mapping = template.variable_mapping || {}
      return nil if mapping.empty?

      var_index = Whatsapp::EventRegistry
        .variables_for(template.event_type_key)
        .index_by { |v| v[:key] }

      mapping
        .sort_by { |position, _| position.to_i }
        .map do |_position, var_key|
          var_def = var_index[var_key]
          { type: 'text', text: (var_def && var_def[:sample]).to_s.presence || "sample_#{var_key}" }
        end
    end

    def component_text(template, type)
      comp = Array(template.components).find do |c|
        c.is_a?(Hash) && c['type'].to_s.casecmp?(type)
      end
      return '' unless comp
      # Header text lives at `text`, body at `text`. Format=TEXT is implicit for body.
      comp['text'].to_s
    end

    def placeholder_slots(text)
      return [] if text.to_s.empty?
      text.scan(/\{\{(\d+)\}\}/).flatten.map(&:to_i).uniq.sort
    end

    # True if any URL button in the registered components has a {{N}} placeholder
    # in its URL — which Meta will require a parameter for at send time.
    def needs_button_param?(template)
      return true if template.url_button_present?

      buttons_comp = Array(template.components).find do |c|
        c.is_a?(Hash) && c['type'].to_s.casecmp?('BUTTONS')
      end
      return false unless buttons_comp

      Array(buttons_comp['buttons']).any? do |b|
        next false unless b.is_a?(Hash) && b['type'].to_s.casecmp?('URL')
        b['url'].to_s.include?('{{')
      end
    end
  end
end
