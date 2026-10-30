# frozen_string_literal: true

module Api
  module Whatsapp
    module Inbox
      class MessagesController < BaseController
        PAGE_SIZE = 50
        POLL_LIMIT = 200
        # Rows are stamped by whichever web/worker host wrote them; the overlap
        # absorbs clock skew so a poll never misses a row (the client merges by id).
        POLL_OVERLAP = 2.seconds
        PARAM_MAX = 1024

        before_action :load_conversation

        def index
          server_time = Time.current
          scope = WhatsappConversationMessage.where(whatsapp_conversation_id: @conversation.id)
                                             .includes(media_file_attachment: :blob)

          if params[:since].present?
            since = parse_time(params[:since])
            return render_error('invalid', 'since must be an ISO8601 time', :bad_request) unless since

            rows = scope.where('whatsapp_conversation_messages.updated_at >= ?', since - POLL_OVERLAP)
                        .order(:occurred_at, :id)
                        .limit(POLL_LIMIT + 1)
                        .to_a
            has_more = rows.size > POLL_LIMIT
            rows = rows.first(POLL_LIMIT)
          else
            limit = params[:limit].present? ? params[:limit].to_i.clamp(1, PAGE_SIZE) : PAGE_SIZE
            if params[:before].present?
              cursor = before_cursor(params[:before])
              return render_error('invalid', 'Invalid before cursor', :bad_request) unless cursor

              scope = scope.where('(whatsapp_conversation_messages.occurred_at, whatsapp_conversation_messages.id) < (?, ?)', cursor[0], cursor[1])
            end
            rows = scope.order(occurred_at: :desc, id: :desc).limit(limit + 1).to_a
            has_more = rows.size > limit
            rows = rows.first(limit).reverse
          end

          render json: {
            messages: serialize(rows),
            conversation: conversation_detail(@conversation),
            server_time: server_time.utc.iso8601(6),
            has_more: has_more
          }
        end

        def create
          message = case params[:type].to_s
                    when 'text' then send_text
                    when 'media' then send_media
                    when 'template' then send_template
                    else return render_error('invalid', 'type must be text, media or template')
                    end
          return if performed?

          render json: { message: serialize([message]).first, conversation: conversation_detail(@conversation.reload) },
                 status: :created
        rescue ::Whatsapp::Inbox::FreeformSender::WindowClosed => e
          render_error('window_closed', e.message.presence || 'The 24-hour reply window has closed')
        rescue ::Whatsapp::Inbox::FreeformSender::NotReady => e
          render_error('not_ready', e.message.presence || "Your WhatsApp number isn't ready to send")
        rescue ::Whatsapp::Inbox::TemplateSender::Invalid => e
          render_error('template_invalid', e.message)
        rescue ::Whatsapp::Inbox::FreeformSender::Invalid => e
          render_error('invalid', e.message)
        rescue ::Whatsapp::Inbox::FreeformSender::SendFailed => e
          render_error('send_failed', e.message, :unprocessable_entity, meta_code_extra(e))
        end

        private

        def send_text
          text = params[:text].to_s
          return render_error('invalid', 'Message is empty') if text.strip.empty?

          reply_to = reply_to_meta_message_id
          return if performed?

          ::Whatsapp::Inbox::FreeformSender.call(
            conversation: @conversation,
            agent: current_agent,
            source: 'agent',
            text: text,
            reply_to_meta_message_id: reply_to,
            resolve: truthy_param?(params[:resolve])
          )
        end

        def send_media
          file = params[:file]
          return render_error('invalid', 'file is required') unless file.respond_to?(:tempfile) && file.respond_to?(:original_filename)

          reply_to = reply_to_meta_message_id
          return if performed?

          ::Whatsapp::Inbox::FreeformSender.call(
            conversation: @conversation,
            agent: current_agent,
            source: 'agent',
            upload: {
              io: file.tempfile,
              filename: File.basename(file.original_filename.to_s),
              content_type: file.content_type.to_s,
              byte_size: file.size.to_i
            },
            caption: params[:caption].to_s.presence,
            reply_to_meta_message_id: reply_to,
            resolve: truthy_param?(params[:resolve])
          )
        end

        def send_template
          template = find_template(params[:template_id])
          return render_error('template_invalid', 'This template can’t be sent from the inbox') unless template

          body_parameters = template_body_parameters(template)
          return if performed?

          ::Whatsapp::Inbox::TemplateSender.call(
            conversation: @conversation,
            agent: current_agent,
            template: template,
            body_parameters: body_parameters,
            resolve: truthy_param?(params[:resolve])
          )
        end

        def find_template(raw_id)
          return nil unless raw_id.to_s.match?(/\A\d+\z/)

          template = inbox_templates(@conversation).find_by(id: raw_id.to_i)
          template if template && inbox_template_pickable?(template)
        end

        # Meta body parameters: one {type: text} per {{n}}, no newlines/tabs and
        # no runs of 4+ spaces, otherwise the send fails with #132000/#100.
        def template_body_parameters(template)
          positions = ::Whatsapp::TemplateComponents.placeholders(
            ::Whatsapp::TemplateComponents.text_of(template.components, 'BODY')
          ).uniq
          values = Array(params[:body_parameters]).map { |v| v.to_s.gsub(/[\r\n\t]+/, ' ').squeeze(' ').strip }
          if values.size != positions.size || values.any?(&:empty?)
            return render_error('template_invalid', 'Fill in every template variable')
          end
          if values.any? { |v| v.length > PARAM_MAX }
            return render_error('template_invalid', "Template variables are limited to #{PARAM_MAX} characters")
          end

          values.map { |v| { 'type' => 'text', 'text' => v } }
        end

        def reply_to_meta_message_id
          raw = params[:reply_to_message_id]
          return nil if raw.blank?
          return render_error('invalid', 'Unknown reply_to_message_id') unless raw.to_s.match?(/\A\d+\z/)

          wamid = WhatsappConversationMessage.where(whatsapp_conversation_id: @conversation.id, id: raw.to_i).pick(:meta_message_id)
          wamid.presence || render_error('invalid', 'That message can’t be replied to')
        end

        def before_cursor(raw)
          if raw.to_s.match?(/\A\d+\z/)
            row = WhatsappConversationMessage.where(whatsapp_conversation_id: @conversation.id, id: raw.to_i).pick(:occurred_at, :id)
            return row
          end

          ::Whatsapp::Inbox::ConversationQuery.decode_cursor(raw)
        end

        def parse_time(raw)
          Time.zone.iso8601(raw.to_s)
        rescue ArgumentError
          nil
        end

        def meta_code_extra(error)
          code = error.respond_to?(:meta_code) ? error.meta_code : nil
          code.present? ? { meta_code: code.to_i } : {}
        end

        def serialize(rows)
          ::Whatsapp::Inbox::MessageSerializer.list(rows, conversation: @conversation, current_agent: current_agent)
        end
      end
    end
  end
end
