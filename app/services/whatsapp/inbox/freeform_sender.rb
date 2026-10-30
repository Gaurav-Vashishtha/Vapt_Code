# frozen_string_literal: true

module Whatsapp
  module Inbox
    # Writes only whatsapp_conversation_messages: free-form replies are never
    # billed, so they must not create whatsapp_message_logs rows.
    class FreeformSender < ApplicationService
      class Error < StandardError; end
      class WindowClosed < Error; end
      class NotReady < Error; end
      class Invalid < Error; end

      class SendFailed < Error
        attr_reader :meta_code

        def initialize(message = nil, meta_code = nil)
          super(message)
          @meta_code = meta_code
        end
      end

      TEXT_LIMIT = 4096
      CAPTION_LIMIT = 1024
      IMAGE_TYPES = %w[image/jpeg image/png].freeze
      IMAGE_MAX_BYTES = 5.megabytes
      DOCUMENT_TYPES = %w[application/pdf].freeze
      DOCUMENT_MAX_BYTES = 16.megabytes
      SOURCES = %w[agent auto_reply system ai].freeze
      REQUEST_TIMEOUT = 20

      def initialize(conversation:, agent:, source:, text: nil, upload: nil, caption: nil,
                     reply_to_meta_message_id: nil, resolve: false)
        @conversation = conversation
        @agent = agent
        @source = source.to_s
        @text = text.to_s.strip
        @upload = upload
        @caption = caption.to_s.strip
        @reply_to_meta_message_id = reply_to_meta_message_id.to_s.presence
        @resolve = resolve ? true : false
      end

      def call
        raise Invalid, "unknown source #{source}" unless SOURCES.include?(source)

        account = conversation.whatsapp_account
        raise NotReady, 'WhatsApp number is not ready to send' unless account&.ready_to_send?

        media = upload ? prepare_upload : nil
        raise Invalid, 'Message is empty' if media.nil? && text.blank?
        raise Invalid, "Message is longer than #{TEXT_LIMIT} characters" if text.length > TEXT_LIMIT
        raise WindowClosed, 'The 24-hour reply window has closed' unless conversation.window_open?

        message = create_message(media)
        payload = request_payload(message, media, account)
        deliver(message, account, payload)
      end

      private

      attr_reader :conversation, :agent, :source, :text, :upload, :caption, :reply_to_meta_message_id, :resolve

      def prepare_upload
        content_type = upload[:content_type].to_s.split(';').first.to_s.strip.downcase
        filename = File.basename(upload[:filename].to_s).presence
        io = upload[:io]
        raise Invalid, 'File is missing' if io.nil?

        kind, limit =
          if IMAGE_TYPES.include?(content_type) then ['image', IMAGE_MAX_BYTES]
          elsif DOCUMENT_TYPES.include?(content_type) then ['document', DOCUMENT_MAX_BYTES]
          else raise Invalid, 'Only JPEG or PNG images and PDF files can be sent'
          end
        raise Invalid, "File is larger than #{limit / 1.megabyte} MB" if upload[:byte_size].to_i > limit

        io.rewind if io.respond_to?(:rewind)
        bytes = io.read(limit + 1).to_s.b
        size = bytes.bytesize
        raise Invalid, 'File is empty' if size.zero?
        raise Invalid, "File is larger than #{limit / 1.megabyte} MB" if size > limit
        raise Invalid, "Caption is longer than #{CAPTION_LIMIT} characters" if caption_text.length > CAPTION_LIMIT

        filename ||= kind == 'image' ? "image.#{content_type.split('/').last}" : 'document.pdf'
        { kind: kind, bytes: bytes, content_type: content_type, filename: filename, size: size }
      end

      def caption_text
        caption.presence || text
      end

      def create_message(media)
        WhatsappConversationMessage.create!(
          whatsapp_conversation_id: conversation.id,
          shop_id: conversation.shop_id,
          direction: :outbound,
          source: source,
          kind: media ? media[:kind] : 'text',
          body: media ? caption_text.presence : text,
          content: {},
          reply_to_meta_message_id: reply_to_meta_message_id,
          agent_id: agent&.id,
          status: :queued,
          media_mime_type: media && media[:content_type],
          media_file_name: media && media[:filename],
          media_size: media && media[:size],
          media_state: :none,
          occurred_at: Time.current
        )
      end

      # Cloud API send shapes: https://developers.facebook.com/docs/whatsapp/cloud-api/reference/messages
      def request_payload(message, media, account)
        payload = {
          messaging_product: 'whatsapp',
          recipient_type: 'individual',
          to: conversation.customer_wa_id
        }
        if media
          media_id = upload_media(message, media, account)
          node = { id: media_id }
          node[:caption] = message.body if message.body.present?
          node[:filename] = media[:filename] if media[:kind] == 'document'
          payload[:type] = media[:kind]
          payload[media[:kind].to_sym] = node
        else
          payload[:type] = 'text'
          payload[:text] = { preview_url: true, body: text }
        end
        payload[:context] = { message_id: reply_to_meta_message_id } if reply_to_meta_message_id
        payload
      end

      def upload_media(message, media, account)
        media_id = Meta::MessagesMediaUploadService.call(
          account: account, bytes: media[:bytes], mime_type: media[:content_type], file_name: media[:filename]
        )
        attrs = { media_id: media_id }
        if MediaStore.enabled?
          begin
            MediaStore.attach!(message, io: StringIO.new(media[:bytes]), filename: media[:filename],
                                        content_type: media[:content_type])
            attrs[:media_state] = :stored
          rescue StandardError => e
            Rails.logger.warn("[Whatsapp::Inbox::FreeformSender] media store failed message=#{message.id}: #{e.class}: #{e.message}")
          end
        end
        message.update!(attrs)
        media_id
      rescue Meta::MessagesMediaUploadService::Error, JSON::ParserError => e
        fail_message!(message, nil, e.message)
        raise SendFailed.new(e.message, nil)
      rescue SocketError, Timeout::Error, Errno::ECONNRESET, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
        fail_message!(message, 'network', e.message)
        raise SendFailed.new("Could not reach WhatsApp: #{e.class}", nil)
      end

      def deliver(message, account, payload)
        client = Meta::GraphClient.new(token: account.system_user_token, timeout: REQUEST_TIMEOUT)
        response = client.post("#{account.phone_number_id}/messages", body: payload)
        meta_id = response.dig('messages', 0, 'id').to_s.presence
        if meta_id.nil?
          fail_message!(message, nil, 'Meta did not return a message id')
          raise SendFailed.new('Meta did not return a message id', nil)
        end

        now = Time.current
        message.update!(meta_message_id: meta_id, status: :sent, sent_at: now)
        WhatsappConversation.touch_last_message!(
          conversation.id, at: message.occurred_at, direction: 'outbound',
                           preview: WhatsappConversationMessage.preview_for(kind: message.kind, body: message.body,
                                                                            file_name: message.media_file_name)
        )
        ConversationState.on_agent_reply!(conversation, agent: agent, at: now, resolve: resolve) if source == 'agent'
        message
      rescue Meta::GraphClient::Error => e
        code = e.code.to_i
        fail_message!(message, code.positive? ? code : e.status, e.message)
        if code == StatusSync::REENGAGEMENT_REQUIRED_CODE
          WhatsappConversation.where(id: conversation.id).update_all(window_closed_hint_at: Time.current, updated_at: Time.current)
          raise WindowClosed, e.message
        end
        raise SendFailed.new(e.message, code.positive? ? code : nil)
      rescue SocketError, Timeout::Error, Errno::ECONNRESET, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
        fail_message!(message, 'network', e.message)
        raise SendFailed.new("Could not reach WhatsApp: #{e.class}", nil)
      end

      def fail_message!(message, code, error_message)
        message.update!(status: :failed, failed_at: Time.current, error_code: code&.to_s, error_message: error_message.to_s.truncate(1000))
      rescue StandardError => e
        Rails.logger.error("[Whatsapp::Inbox::FreeformSender] could not mark message=#{message.id} failed: #{e.class}: #{e.message}")
      end
    end
  end
end
