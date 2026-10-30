require 'httparty'

module Meta
  class TemplateService < ApplicationService
    class Error < StandardError; end

    OPERATIONS = %i[create list sync delete edit].freeze

    CUTLY_BASE = 'https://cutt.ly/'.freeze
    CUTLY_TEMPLATE_URL = "#{CUTLY_BASE}{{1}}".freeze
    CUTLY_EXAMPLE_URL  = "#{CUTLY_BASE}abc123".freeze

    def initialize(account:, operation:, attrs: {}, template: nil)
      raise ArgumentError, "unknown operation #{operation}" unless OPERATIONS.include?(operation)

      @account = account
      @operation = operation
      @attrs = (attrs.respond_to?(:to_unsafe_h) ? attrs.to_unsafe_h : attrs.to_h).with_indifferent_access
      @template = template
    end

    def call
      raise Error, 'no WABA id on account' if account.waba_id.blank?

      send(operation)
    rescue Meta::GraphClient::Error => e
      raise Error, e.message
    end

    # True only when Meta's reported category for a template can NOT be used by
    # the event the local row is bound to.
    #
    # Several events accept more than one category — abandoned_cart is bindable
    # as UTILITY *or* MARKETING — and Meta auto-upgrades UTILITY -> MARKETING
    # during review when the body skews promotional. The previous sync check
    # compared against the single default category (compatible_category) and
    # treated that legitimate upgrade as a mismatch, wiping variable_mapping +
    # url_button. Every subsequent send then failed with Meta 131008 ("required
    # parameter is missing") because the recovery-URL button param was dropped.
    #
    # Compare against the full bindable set instead, matching the model
    # validation (WhatsappTemplate#category_matches_event_type) and the bind
    # endpoint. An empty/unknown bindable set means "we can't judge" -> never
    # force a detach.
    def self.incompatible_meta_category?(event_type_key, meta_category)
      allowed = Whatsapp::EventRegistry.bindable_categories_for(event_type_key)
      return false if allowed.blank?

      allowed.none? { |c| c.to_s.casecmp?(meta_category.to_s) }
    end

    private

    attr_reader :account, :operation, :attrs, :template

    def create
      ensure_cod_verification_buttons!(attrs[:event_type_key], attrs[:components])
      url_button_config = attrs[:url_button].presence
      # Prefer the explicit header_media blob from the form (carries handle +
      # media_id for upload-mode); fall back to extracting from components for
      # callers that don't supply it.
      header_media_config = attrs[:header_media].presence || extract_header_media(attrs[:components])
      components = rewrite_url_button_for_meta(attrs[:components] || [], url_button_config)

      # Meta's template review requires example.header_handle to be a handle
      # from the Resumable Upload API; a raw public URL is rejected on strict
      # accounts ("Missing sample parameter for title type"). Resolve any pasted
      # URL to a real handle for the create payload ONLY — the persisted
      # components keep the URL so send-time media (image.link) still works
      # (resumable handles are invalid at send time).
      meta_components = resolve_header_handles(components)

      payload = {
        name: attrs[:name],
        language: attrs[:language] || 'en_US',
        category: attrs[:category],
        components: meta_components
      }

      response = account.graph_client.post("#{account.waba_id}/message_templates", body: payload)

      record = account.whatsapp_templates.find_or_initialize_by(name: payload[:name], language: payload[:language])
      record.assign_attributes(
        meta_template_id: response['id'],
        category: payload[:category],
        components: components,
        status: meta_status_to_enum(response['status']),
        event_type_key: attrs[:event_type_key].presence,
        variable_mapping: attrs[:variable_mapping] || {},
        url_button: url_button_config,
        header_media: header_media_config,
        last_synced_at: Time.current
      )
      record.save!
      record
    end

    def list
      account.whatsapp_templates.order(updated_at: :desc)
    end

    def sync
      response = account.graph_client.get(
        "#{account.waba_id}/message_templates",
        query: { fields: 'id,name,language,category,status,components,quality_score,rejected_reason', limit: 200 }
      )

      data = response['data'] || []
      data.each do |t|
        record = account.whatsapp_templates.find_or_initialize_by(name: t['name'], language: t['language'])
        record.assign_attributes(
          meta_template_id: t['id'],
          category: t['category'],
          components: t['components'] || [],
          status: meta_status_to_enum(t['status']),
          rejection_reason: t['rejected_reason'],
          last_synced_at: Time.current
        )

        # If Meta's reported category is genuinely incompatible with the event
        # the local row is bound to, drop the local binding (and dependent
        # state) so the sync still succeeds. Meta is authoritative; the merchant
        # can re-bind. A merely *different-but-allowed* category (e.g. Meta
        # auto-upgrading an abandoned_cart template UTILITY -> MARKETING) must
        # NOT detach — see incompatible_meta_category? for the full rationale.
        if record.event_type_key.present? &&
           self.class.incompatible_meta_category?(record.event_type_key, t['category'])
          allowed = Whatsapp::EventRegistry.bindable_categories_for(record.event_type_key)
          Rails.logger.warn("[whatsapp/sync] template=#{record.name}/#{record.language} meta_category=#{t['category']} not bindable for event=#{record.event_type_key} (allowed #{allowed.inspect}); detaching binding")
          record.event_type_key = nil
          record.variable_mapping = {}
          record.url_button = nil
        end

        record.save!
      end

      account.whatsapp_templates.reload
    end

    def delete
      raise Error, 'template required' unless template

      if template.meta_template_id.present?
        account.graph_client.delete(
          "#{account.waba_id}/message_templates",
          query: { name: template.name }
        )
      end
      template.destroy!
      true
    end

    # Edit an existing template's content on Meta. POSTs to /{template_id}
    # with components + (optionally) category. After approval the template
    # goes back through PENDING review.
    #
    # Meta constraints to be aware of:
    #   - Name / language can't be edited; we don't expose them here.
    #   - Up to 10 edits per day, 10 per month per template.
    #   - Only APPROVED / REJECTED / PAUSED templates are editable.
    def edit
      raise Error, 'template required' unless template
      raise Error, 'template has no Meta ID — it was never submitted' if template.meta_template_id.blank?
      ensure_cod_verification_buttons!(template.event_type_key, attrs[:components])

      url_button_config = attrs[:url_button].presence
      header_media_config = attrs[:header_media].presence || extract_header_media(attrs[:components])
      components = rewrite_url_button_for_meta(attrs[:components] || [], url_button_config)

      meta_components = resolve_header_handles(components)

      body = { components: meta_components }
      body[:category] = attrs[:category] if attrs[:category].present?

      account.graph_client.post(template.meta_template_id.to_s, body: body)

      # Meta returns { success: true } on accepted edits; the template moves
      # back to PENDING until re-reviewed. The full status update will arrive
      # via the message_template_status_update webhook.
      template.assign_attributes(
        components: components,
        category: attrs[:category].presence || template.category,
        status: :pending,
        rejection_reason: nil,
        variable_mapping: attrs[:variable_mapping].presence || template.variable_mapping,
        url_button: url_button_config || template.url_button,
        header_media: header_media_config || template.header_media,
        last_synced_at: Time.current
      )
      template.save!
      template
    end

    # Pulls the merchant's chosen media reference (upload handle or URL) out of
    # the HEADER component so it survives Meta-side syncs that would otherwise
    # replace `example.header_handle` with a temporary CDN URL.
    def ensure_cod_verification_buttons!(event_type_key, components)
      return unless event_type_key.to_s == 'cod_verification'

      error = Whatsapp::CodVerificationButtons.mapping_error(components)
      raise Error, error if error
    end

    def extract_header_media(components)
      header = Array(components).find { |c| c.is_a?(Hash) && c['type'].to_s.casecmp?('HEADER') }
      return nil unless header

      format = header['format'].to_s.upcase
      return nil unless %w[IMAGE VIDEO DOCUMENT].include?(format)

      value = header.dig('example', 'header_handle')&.first
      return nil if value.blank?

      kind = value.to_s.start_with?('http') ? 'url' : 'handle'
      { 'format' => format, 'source' => kind, 'value' => value }
    end

    # Returns a copy of `components` where any IMAGE/VIDEO/DOCUMENT header whose
    # example.header_handle is a raw public URL is replaced with a real handle
    # obtained from Meta's Resumable Upload API. Non-URL handles (already
    # uploaded) and text headers pass through untouched. Used only for the
    # create payload — never for the persisted record.
    def resolve_header_handles(components)
      Array(components).map do |c|
        next c unless c.is_a?(Hash) && c['type'].to_s.casecmp?('HEADER')

        format = c['format'].to_s.upcase
        next c unless %w[IMAGE VIDEO DOCUMENT].include?(format)

        value = c.dig('example', 'header_handle')&.first
        next c if value.blank? || !value.to_s.start_with?('http')

        handle = upload_url_for_handle(value, format)
        merged_example = (c['example'] || {}).merge('header_handle' => [handle])
        c.merge('example' => merged_example)
      end
    end

    # Downloads the pasted sample URL server-side and pushes the bytes through
    # the Resumable Upload API to get a handle Meta accepts for template review.
    def upload_url_for_handle(url, format)
      resp = HTTParty.get(url, follow_redirects: true)
      raise Error, "could not download header sample from #{url} (HTTP #{resp.code})" unless resp.success?

      mime = resp.headers['content-type'].to_s.split(';').first.presence || default_mime_for(format)
      file_name = File.basename(URI.parse(url).path).presence || 'header_sample'

      Meta::ResumableUploadService.call(
        account: account,
        bytes: resp.body.to_s.b,
        mime_type: mime,
        file_name: file_name
      )
    rescue Meta::ResumableUploadService::Error => e
      raise Error, "could not prepare header sample: #{e.message}"
    end

    def default_mime_for(format)
      case format
      when 'IMAGE'    then 'image/jpeg'
      when 'VIDEO'    then 'video/mp4'
      when 'DOCUMENT' then 'application/pdf'
      else 'application/octet-stream'
      end
    end

    # Rewrites the merchant-supplied BUTTONS component so every URL button
    # whose destination is dynamic (Mode A or Mode B) is registered with Meta
    # as `https://cutt.ly/{{1}}`. The merchant's intent is persisted on
    # `whatsapp_templates.url_button` and resolved to a slug at send time.
    def rewrite_url_button_for_meta(components, url_button_config)
      return components if url_button_config.blank?

      components.map do |c|
        next c unless c.is_a?(Hash) && c['type'].to_s.casecmp?('BUTTONS')

        new_buttons = Array(c['buttons']).map do |b|
          next b unless b.is_a?(Hash) && b['type'].to_s.casecmp?('URL')

          b.merge(
            'type' => 'URL',
            'text' => url_button_config['text'] || b['text'],
            'url'  => CUTLY_TEMPLATE_URL,
            'example' => [CUTLY_EXAMPLE_URL]
          )
        end

        c.merge('buttons' => new_buttons)
      end
    end

    def meta_status_to_enum(status)
      case status.to_s.upcase
      when 'APPROVED' then :approved
      when 'REJECTED' then :rejected
      when 'PAUSED'   then :paused
      when 'DISABLED' then :disabled
      else :pending
      end
    end
  end
end
