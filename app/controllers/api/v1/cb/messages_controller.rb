# frozen_string_literal: true

module Api
  module V1
    module Cb
      class MessagesController < BaseController
        API_EVENT_KEY = 'custom_branded_api'

        # POST /api/v1/cb/messages
        # {
        #   template_id | (template_name + language),
        #   to, variables: {"1" => "...", ...} | [..],
        #   account_id?, header_image_url?, header_video_url?, header_document_url?,
        #   button_param?, idempotency_key?
        # }
        # Validates everything that can be validated synchronously (so the
        # caller gets a 422, not a silently failed queue job), then enqueues
        # the existing Whatsapp::SendTemplateMessageJob.
        def create
          to = params[:to].to_s.gsub(/\D/, '')
          return render_error('to (recipient phone) is required') if to.blank?

          template, account = resolve_template_and_account
          if template.nil? && params[:template_id].blank? && params[:template_name].blank? && params[:event_id].present?
            return render_error('no_active_template_for_event', :unprocessable_entity,
                                detail: "No active template is mapped to event #{params[:event_id]} for this brand.")
          end
          return render_error('template not found', :not_found) if template.nil?
          return render_error('no WhatsApp account connected for this shop', :not_found) if account.nil?

          unless account.ready_to_send?
            return render_error(
              account.needs_registration? ? 'account_not_registered' : 'account_not_ready',
              :unprocessable_entity,
              detail: 'The WhatsApp number is not ready to send. Check registration on the portal.'
            )
          end
          unless template.approved?
            return render_error('template_not_approved', :unprocessable_entity,
                                detail: "Template status is #{template.status}.")
          end

          # Body / header / button parameters + validation live in
          # CustomBranded::TemplateSendParams (shared with the portal's test
          # send) so both surfaces accept and reject the same input.
          send_params = ::CustomBranded::TemplateSendParams.call(template: template, params: params)
          unless send_params.ok?
            return render_error(send_params.error, :unprocessable_entity, detail: send_params.detail)
          end

          idempotency_key = params[:idempotency_key].presence

          # The partial unique index idx_whatsapp_logs_unique_per_send already
          # dedupes on (shop, event, source_external_id, stage) — reuse it: a
          # repeated idempotency_key returns the original log instead of
          # sending twice.
          if idempotency_key
            existing = client.whatsapp_message_logs.where(
              event_type_key: API_EVENT_KEY,
              source_external_id: idempotency_key,
              stage_index: 0
            ).where.not(status: :failed).first
            if existing
              return render json: serialize_log(existing).merge(duplicate: true), status: :ok
            end
          end

          # ::-anchored: bare Whatsapp:: would resolve to Api::Whatsapp (the
          # embedded controllers' module) from inside Api::V1::Cb.
          ::Whatsapp::SendTemplateMessageJob.perform_async(
            account.id, template.id, to,
            send_params.body_parameters, send_params.header_parameters,
            API_EVENT_KEY,
            { 'api' => true, 'variables' => send_params.raw_variables },
            nil,
            0,
            idempotency_key,
            0,
            send_params.quick_reply_button_params,
            send_params.url_button_params
          )

          render json: { status: 'queued', shop_domain: client.domain,
                         template: template.name, to: to,
                         idempotency_key: idempotency_key }, status: :accepted
        end

        # GET /api/v1/cb/messages — message history, newest first.
        # Filters: status (queued|sent|delivered|read|failed), to (recipient),
        # template_id. Pagination: limit (default 25, max 100) + before_id
        # cursor (pass the smallest message_id from the previous page).
        def index
          scope = client.whatsapp_message_logs.recent
          scope = scope.where(status: params[:status]) if params[:status].present? && WhatsappMessageLog.statuses.key?(params[:status])
          scope = scope.where(recipient: params[:to].to_s.gsub(/\D/, '')) if params[:to].present?
          scope = scope.where(whatsapp_template_id: params[:template_id]) if params[:template_id].present?
          scope = scope.where('id < ?', params[:before_id].to_i) if params[:before_id].present?

          limit = params[:limit].to_i.clamp(1, 100)
          limit = 25 if params[:limit].blank?
          logs = scope.limit(limit).to_a

          render json: {
            messages: logs.map { |l| serialize_log(l) },
            next_before_id: (logs.last.id if logs.size == limit)
          }
        end

        # GET /api/v1/cb/messages/:id
        # :id is the WhatsappMessageLog id, or an idempotency key (prefix
        # lookup by source_external_id) so async callers can poll either way.
        def show
          log = client.whatsapp_message_logs.find_by(id: params[:id]) ||
                client.whatsapp_message_logs.where(event_type_key: API_EVENT_KEY,
                                                 source_external_id: params[:id]).recent.first
          return render_error('message not found', :not_found) if log.nil?

          render json: serialize_log(log)
        end

        private

        # A template exists on exactly one number's WABA and can only be sent
        # from that number, so template_id fully determines the account. With
        # template_name, the number (account_id param or shop default) picks
        # which WABA the name is looked up on.
        def resolve_template_and_account
          if params[:template_id].present?
            template = client.whatsapp_templates.find_by(id: params[:template_id])
            [template, template&.whatsapp_account]
          elsif params[:template_name].present?
            account = if params[:account_id].present?
                        client.whatsapp_accounts.find_by(id: params[:account_id])
                      else
                        client.default_whatsapp_account
                      end
            return [nil, account] if account.nil?

            scope = account.whatsapp_templates.where(name: params[:template_name].to_s)
            scope = scope.where(language: params[:language].to_s) if params[:language].present?
            [scope.first, account]
          elsif params[:event_id].present?
            template = CustomBrandedTemplateEvent.active_for(client, params[:event_id])&.whatsapp_template
            [template, template&.whatsapp_account]
          else
            [nil, nil]
          end
        end

        def serialize_log(log)
          {
            message_id: log.id,
            status: log.status,
            template: log.template_name,
            recipient: log.recipient,
            meta_message_id: log.meta_message_id,
            error_code: log.error_code,
            error_message: log.error_message,
            sent_at: log.sent_at,
            delivered_at: log.delivered_at,
            read_at: log.read_at,
            failed_at: log.failed_at,
            created_at: log.created_at
          }
        end

        def render_error(error, status = :bad_request, detail: nil)
          payload = { error: error }
          payload[:detail] = detail if detail
          render json: payload, status: status
        end
      end
    end
  end
end
