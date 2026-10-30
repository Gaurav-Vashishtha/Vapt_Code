module Whatsapp
  # Re-sends the exact message behind a WhatsappMessageLog row (the "Retry"
  # action on the Logs page). Produces a NEW log row linked back to the
  # original via payload_snapshot['retry_of_log_id'] — the original is never
  # mutated, so delivery history stays honest.
  #
  # The send is replayed from what the original row captured:
  #   * body parameters   — payload_snapshot['body_parameters'] (always stored)
  #   * header / buttons  — payload_snapshot['send_request'] (stored since the
  #                         Retry feature); older rows re-resolve them from the
  #                         event payload + template config instead.
  #
  # Runs inline (synchronously) so the caller gets the outcome immediately.
  class ResendMessageLogService < ApplicationService
    class Error < StandardError; end

    # in_place: resend onto the same row (automatic WhatsApp retries) instead
    # of creating a linked new row (the Logs page Retry button).
    def initialize(log:, shop: nil, in_place: false)
      @log = log
      @shop = shop || log&.shop
      @in_place = in_place
    end

    def call
      raise Error, 'log not found' if log.nil?
      raise Error, 'template no longer exists — cannot rebuild this message' if template.nil?
      raise Error, 'template is not approved on Meta' unless template.approved?
      raise Error, 'recipient is missing on this log' if log.recipient.blank?

      account = sendable_account
      raise Error, 'no WhatsApp number is ready to send' if account.nil?

      snapshot = snapshot_payload
      request = snapshot['send_request'].is_a?(Hash) ? snapshot['send_request'] : {}

      body_parameters = Array(snapshot['body_parameters'])
      body_parameters = VariableResolver.call(template: template, payload: snapshot) if body_parameters.empty?

      header_parameters = request['header_parameters'].presence || resolve_header_parameters(snapshot)
      button_slug = request.key?('button_slug') ? request['button_slug'] : resolve_button_slug(snapshot)

      replay_snapshot = snapshot.except('body_parameters', 'send_request').merge(
        'retry_of_log_id' => log.id,
        'retry_attempt' => (snapshot['retry_attempt'].to_i + 1)
      )

      # source_external_id is deliberately nil: the partial unique index
      # (shop, event, source, stage) would otherwise refuse a second non-failed
      # row for the same order. The link back lives in retry_of_log_id.
      new_log = ::Meta::SendTemplateMessageService.call(
        account: account,
        template: template,
        recipient: log.recipient,
        body_parameters: body_parameters,
        header_parameters: header_parameters,
        event_type_key: log.event_type_key,
        payload_snapshot: replay_snapshot,
        button_slug: button_slug,
        stage_index: log.stage_index.to_i,
        source_external_id: nil,
        button_index: request['button_index'].to_i,
        quick_reply_button_params: request['quick_reply_button_params'],
        url_button_params: request['url_button_params'],
        existing_log: (@in_place ? log : nil)
      )
      raise Error, 'send was skipped' if new_log.nil?
      return new_log if @in_place

      new_log.update_columns(whatsapp_campaign_id: log.whatsapp_campaign_id) if log.respond_to?(:whatsapp_campaign_id) && log.whatsapp_campaign_id.present?
      new_log
    rescue ::Meta::SendTemplateMessageService::Error => e
      raise Error, e.message
    end

    private

    attr_reader :log, :shop

    def template
      @template ||= log.whatsapp_template
    end

    def sendable_account
      original = log.whatsapp_account
      return original if original&.ready_to_send?

      fallback = shop&.default_whatsapp_account
      fallback if fallback&.ready_to_send?
    end

    def snapshot_payload
      snap = log.payload_snapshot
      snap.is_a?(Hash) ? snap.deep_stringify_keys : {}
    end

    def resolve_header_parameters(payload)
      media_param = template.media_header_param(payload, shop)
      media_param ? [media_param] : nil
    end

    def resolve_button_slug(payload)
      UrlButtonResolver.call(template: template, payload: payload)
    end
  end
end
