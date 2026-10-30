module Meta
  # Generalised template-message sender. Used by both event dispatch and manual test sends.
  # Returns the created WhatsappMessageLog row.
  class SendTemplateMessageService < ApplicationService
    class Error < StandardError; end

    ACCOUNT_NOT_REGISTERED_CODE = 133_010

    def initialize(account:, template:, recipient:, body_parameters: nil, header_parameters: nil,
                   event_type_key: nil, payload_snapshot: {}, button_slug: nil,
                   stage_index: 0, source_external_id: nil, button_index: 0,
                   quick_reply_button_params: nil, url_button_params: nil, existing_log: nil)
      @account = account
      # Resend onto this row instead of creating a new one (WhatsApp retries).
      @existing_log = existing_log
      @template = template
      @recipient = recipient
      @body_parameters = body_parameters
      @header_parameters = header_parameters
      @event_type_key = event_type_key || template&.event_type_key
      @payload_snapshot = payload_snapshot
      @button_slug = button_slug
      @stage_index = stage_index
      @source_external_id = source_external_id
      @button_index = button_index
      @quick_reply_button_params = quick_reply_button_params
      @url_button_params = url_button_params
    end

    def call
      raise Error, 'account is not ready to send' unless account.ready_to_send?
      raise Error, 'template is required' if template.nil?
      raise Error, 'recipient is required' if recipient.blank?

      if existing_log
        log = existing_log
        log.update_columns(status: WhatsappMessageLog.statuses['queued'], updated_at: Time.current)
      else
        log = build_log(:queued)
      end

      # The partial unique index `idx_whatsapp_logs_unique_per_send` prevents
      # two concurrent dispatchers from both creating a non-failed log row for
      # the same (shop, event, source, stage) tuple. Whichever loses the race
      # gets RecordNotUnique on save — that means the other dispatcher already
      # made the Meta call, so we abort without sending. Returns nil so callers
      # can distinguish "dedup-aborted" from "sent" cleanly.
      begin
        log.save! unless existing_log
      rescue ActiveRecord::RecordNotUnique
        Rails.logger.info(
          "[whatsapp/send] dedup race lost — another dispatcher already sent " \
          "shop=#{account.shop_id} event=#{event_type_key} " \
          "source=#{source_external_id} stage=#{stage_index}"
        )
        return nil
      end

      # Meta rejects a message from a business number to itself with an opaque
      # "(#100) Invalid parameter" — usually a test order placed with the
      # store's own WhatsApp number. Fail it with a readable reason instead.
      if sending_to_self?
        reason = "Recipient #{normalize_phone(recipient)} is this WhatsApp business number itself — " \
                 'WhatsApp cannot send a message from a number to itself. Use a different customer phone.'
        log.update!(status: :failed, failed_at: Time.current, error_code: 'self_recipient', error_message: reason)
        raise Error, reason
      end

      materialized = materialize_header_media(header_parameters)
      body = request_body(build_components(materialized))
      attempts = []

      begin
        response = post_message(body, attempts)
        meta_id = response.dig('messages', 0, 'id')
        log.update!(meta_message_id: meta_id, status: :sent, sent_at: Time.current)
      rescue Meta::GraphClient::Error => e
        # A pre-uploaded header media id that Meta refuses (#100) falls back to
        # the original link once, so a bad upload never blocks the message.
        if attempts.size == 1 && e.code.to_i == INVALID_PARAMETER_CODE &&
           header_parameters.present? && materialized != Array(header_parameters)
          Rails.logger.warn("[whatsapp/send] log=#{log.id} #100 with uploaded header media id — retrying with the original link")
          body = request_body(build_components(header_parameters))
          retry
        end
        record_attempts(log, attempts)
        log.update!(
          status: :failed,
          failed_at: Time.current,
          error_code: (e.code || e.status).to_s,
          error_message: e.message
        )
        flag_unregistered_account(e)
        raise Error, e.message
      end

      record_attempts(log, attempts)
      log
    end

    INVALID_PARAMETER_CODE = 100

    private

    def sending_to_self?
      own = account.display_phone_number.to_s.gsub(/\D/, '').sub(/\A0+/, '')
      own.present? && own == normalize_phone(recipient)
    end

    def request_body(components)
      body = {
        messaging_product: 'whatsapp',
        to: normalize_phone(recipient),
        type: 'template',
        template: {
          name: template.name,
          language: { code: template.language }
        }
      }
      body[:template][:components] = components if components.any?
      body
    end

    # Posts the message and remembers exactly what went to Meta and what came
    # back, so the Logs page can show the real request (after the header link
    # was swapped for an uploaded media id) and Meta's full error.
    def post_message(body, attempts)
      entry = { 'request' => body.deep_stringify_keys['template'] }
      attempts << entry
      response = account.graph_client.post("#{account.phone_number_id}/messages", body: body)
      entry['ok'] = true
      response
    rescue Meta::GraphClient::Error => e
      entry['ok'] = false
      entry['error'] = e.body.is_a?(Hash) ? e.body['error'] : e.message
      raise
    end

    def record_attempts(log, attempts)
      return if attempts.empty?

      snap = log.payload_snapshot.is_a?(Hash) ? log.payload_snapshot.deep_dup : {}
      snap['meta_attempts'] = attempts
      log.update_columns(payload_snapshot: snap)
    rescue StandardError => e
      Rails.logger.warn("[whatsapp/send] could not record meta attempts on log #{log&.id}: #{e.message}")
    end

    attr_reader :account, :template, :recipient, :body_parameters, :header_parameters,
                :event_type_key, :payload_snapshot, :button_slug,
                :stage_index, :source_external_id, :button_index, :quick_reply_button_params,
                :url_button_params, :existing_log

    # #133010 means the number was never registered on Cloud API, which no
    # retry can fix — every subsequent send fails identically. Record it on the
    # account so ready_to_send? goes false and callers route around this number
    # instead of silently dropping messages.
    def flag_unregistered_account(error)
      return unless error.code.to_i == ACCOUNT_NOT_REGISTERED_CODE
      return unless account.registered?

      account.mark_unregistered!(reason: error.message)
      SlackNotifyJob.perform_async(
        ":rotating_light: WhatsApp number NOT REGISTERED (#{Rails.env}) " \
        "shop_id=#{account.shop_id} account=#{account.id} " \
        "phone_number_id=#{account.phone_number_id} display=#{account.display_phone_number}\n" \
        "Meta: #{error.message}. BSP sends now fall back until the 6-digit PIN " \
        "registration is completed on the Account page."
      )
    rescue StandardError => e
      Rails.logger.warn("[whatsapp/send] could not flag unregistered account #{account.id}: #{e.message}")
    end

    def build_log(initial_status)
      # Persist the resolved body parameters alongside the raw payload snapshot
      # so the Logs UI can render the message body with the actual values that
      # were sent, instead of the raw {{N}} placeholders.
      snapshot =
        if payload_snapshot.is_a?(Hash)
          payload_snapshot.deep_dup.merge('body_parameters' => Array(body_parameters))
        else
          { 'body_parameters' => Array(body_parameters) }
        end
      # Everything else needed to replay this exact send (Retry on the Logs
      # page). Body params are above; the payload itself is the snapshot.
      snapshot['send_request'] = {
        'header_parameters' => (header_parameters.present? ? Array(header_parameters).as_json : nil),
        'button_slug' => button_slug.presence,
        'button_index' => button_index.to_i,
        'url_button_params' => (url_button_params.present? ? Array(url_button_params).as_json : nil),
        'quick_reply_button_params' => (quick_reply_button_params.present? ? Array(quick_reply_button_params).as_json : nil)
      }.compact

      WhatsappMessageLog.new(
        # Ownership mirrors the account: exactly one of shop_id /
        # custom_branded_client_id is set.
        shop_id: account.shop_id,
        custom_branded_client_id: account.custom_branded_client_id,
        whatsapp_account_id: account.id,
        whatsapp_template_id: template.id,
        event_type_key: event_type_key.to_s,
        template_name: template.name,
        recipient: recipient.to_s,
        status: initial_status,
        payload_snapshot: snapshot,
        stage_index: stage_index,
        source_external_id: source_external_id
      )
    end

    # WhatsApp template media headers accept only these mime types. Notably
    # NOT image/webp — which is exactly what Shopify's CDN serves via content
    # negotiation for a `.jpg` URL when the fetcher advertises webp support.
    UPLOADABLE_MEDIA_MIME = %w[image/jpeg image/png video/mp4 application/pdf].freeze

    # Replace any media header that points at a `link` with an uploaded
    # `media_id`. Sending by link makes Meta fetch the URL itself (and fail with
    # 131053 "Media upload error" on Shopify webp/redirect/size quirks); sending
    # by id hands Meta the bytes directly. We fetch with an explicit Accept so
    # Shopify returns JPEG/PNG rather than webp. Best-effort: on any failure we
    # leave the original link param untouched, so this never makes a send worse.
    def materialize_header_media(params)
      Array(params).map do |p|
        next p unless p.is_a?(Hash)

        kind  = p['type'].to_s            # 'image' | 'video' | 'document'
        media = p[kind]
        next p unless media.is_a?(Hash)

        link = media['link']
        next p if link.blank? || media['id'].present?

        media_id = link_to_media_id(link, kind)
        media_id.present? ? p.merge(kind => { 'id' => media_id }) : p
      end
    end

    def link_to_media_id(link, kind)
      cache_key = "whatsapp/media_id/#{account.id}/#{Digest::MD5.hexdigest(link.to_s)}"
      Rails.cache.fetch(cache_key, expires_in: 6.hours, skip_nil: true) do
        accept = kind == 'image' ? 'image/jpeg,image/png' : '*/*'
        resp = HTTParty.get(link, headers: { 'Accept' => accept }, timeout: 25, follow_redirects: true)
        raise Meta::MessagesMediaUploadService::Error, "fetch returned HTTP #{resp.code}" unless resp.success?

        mime = resp.headers['content-type'].to_s.split(';').first.to_s.strip.downcase
        mime = infer_mime_from_link(link) if mime.blank? || mime == 'application/octet-stream'
        unless UPLOADABLE_MEDIA_MIME.include?(mime)
          raise Meta::MessagesMediaUploadService::Error, "unsupported media type #{mime.inspect} for #{link}"
        end

        Meta::MessagesMediaUploadService.call(account: account, bytes: resp.body, mime_type: mime)
      end
    rescue => e
      Rails.logger.warn("[whatsapp/send] media pre-upload failed kind=#{kind} link=#{link}: #{e.class}: #{e.message}")
      nil
    end

    def infer_mime_from_link(link)
      case link.to_s.downcase.split('?').first
      when /\.png\z/   then 'image/png'
      when /\.jpe?g\z/ then 'image/jpeg'
      when /\.mp4\z/   then 'video/mp4'
      when /\.pdf\z/   then 'application/pdf'
      when /\.webp\z/  then 'image/webp'
      else ''
      end
    end

    def build_components(header_params = header_parameters)
      out = []
      out << { 'type' => 'header', 'parameters' => header_params } if header_params&.any?
      out << { 'type' => 'body', 'parameters' => body_parameters } if body_parameters&.any?
      # URL button params. A template can carry SEVERAL dynamic URL buttons
      # (each with a {{n}} suffix) and Meta requires a parameter for every one
      # of them, at its real index within the buttons list — otherwise #131008.
      # `url_button_params` ([{'index' =>, 'param' =>}]) covers the general
      # case (custom-branded API); `button_slug`/`button_index` is the legacy
      # single-button path used by event dispatch.
      if url_button_params.present?
        url_button_params.each do |p|
          next unless p.is_a?(Hash)

          out << {
            'type' => 'button',
            'sub_type' => 'url',
            'index' => p['index'].to_i.to_s,
            'parameters' => [{ 'type' => 'text', 'text' => p['param'].to_s }]
          }
        end
      elsif button_slug.present?
        out << {
          'type' => 'button',
          'sub_type' => 'url',
          'index' => button_index.to_i.to_s,
          'parameters' => [{ 'type' => 'text', 'text' => button_slug.to_s }]
        }
      end
      # Without an explicit payload Meta echoes the button text back, which the
      # webhook can't route. COD verification payloads are keyed to what each
      # button says, never its position: a positional map turned a Confirm tap
      # into a cancel whenever a template listed Cancel first.
      if quick_reply_button_params.present?
        quick_reply_button_params.each do |p|
          next unless p.is_a?(Hash)

          out << {
            'type' => 'button',
            'sub_type' => 'quick_reply',
            'index' => p['index'].to_i.to_s,
            'parameters' => [{ 'type' => 'payload', 'payload' => p['payload'].to_s }]
          }
        end
      elsif %w[cod_verification cod_verification_reminder].include?(template.event_type_key.to_s)
        ::Whatsapp::CodVerificationButtons.payload_params(template.components).each do |p|
          out << {
            'type' => 'button',
            'sub_type' => 'quick_reply',
            'index' => p['index'].to_s,
            'parameters' => [{ 'type' => 'payload', 'payload' => p['payload'] }]
          }
        end
      else
        quick_reply_payloads = required_quick_reply_payloads_from_template
        quick_reply_payloads.each_with_index do |payload, idx|
          out << {
            'type' => 'button',
            'sub_type' => 'quick_reply',
            'index' => idx.to_s,
            'parameters' => [{ 'type' => 'payload', 'payload' => payload }]
          }
        end
      end
      out
    end

    # Reads the fixed payloads required by the template's bound event (e.g.
    # cod_verification → ['cod_confirm', 'cod_cancel']). Returns [] for events
    # with no fixed-payload requirement.
    def required_quick_reply_payloads_from_template
      ::Whatsapp::EventRegistry.required_quick_reply_payloads_for(template.event_type_key)
    end

    def normalize_phone(value)
      value.to_s.gsub(/\D/, '').sub(/\A0+/, '')
    end
  end
end
