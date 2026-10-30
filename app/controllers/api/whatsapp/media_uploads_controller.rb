module Api
  module Whatsapp
    class MediaUploadsController < AuthenticatedController
      before_action :load_account

      MAX_BYTES = 16 * 1024 * 1024 # 16 MiB — Meta's image limit; videos/docs can be larger but use the same cap for safety
      ALLOWED_MIME_PREFIXES = %w[image/ video/ application/pdf].freeze

      def create
        file = params[:file]
        return render(json: { error: 'file is required' }, status: :bad_request) unless file.respond_to?(:read)

        if file.size.to_i > MAX_BYTES
          return render(json: { error: "file exceeds #{MAX_BYTES / 1024 / 1024} MB" }, status: :unprocessable_entity)
        end

        content_type = file.content_type.to_s
        unless ALLOWED_MIME_PREFIXES.any? { |p| content_type.start_with?(p) }
          return render(json: { error: "unsupported content type: #{content_type}" }, status: :unprocessable_entity)
        end

        # Read the bytes once and feed both upload APIs:
        # - Resumable upload → handle for template review (`example.header_handle`).
        # - Messages media   → media_id for send-time `image.id` / `video.id` / `document.id`.
        bytes = file.tempfile.read.b

        handle = Meta::ResumableUploadService.call(
          account: @account,
          bytes: bytes,
          mime_type: content_type,
          file_name: file.original_filename
        )

        media_id =
          begin
            Meta::MessagesMediaUploadService.call(
              account: @account,
              bytes: bytes,
              mime_type: content_type,
              file_name: file.original_filename
            )
          rescue Meta::MessagesMediaUploadService::Error => e
            Rails.logger.warn("[api/whatsapp/media_uploads] messages media upload failed: #{e.message}")
            nil # template can still be created with just the resumable handle; sends will fall back
          end

        render json: {
          handle: handle,
          media_id: media_id,
          file_name: file.original_filename,
          content_type: content_type
        }
      rescue Meta::ResumableUploadService::Error => e
        Rails.logger.warn("[api/whatsapp/media_uploads] upload failed: #{e.message}")
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      # Media uploads produce a phone-number-specific media_id, so target the
      # number the template is being created under (account_id), default
      # otherwise.
      def load_account
        @account = if params[:account_id].present?
                     @shop.whatsapp_accounts.find_by(id: params[:account_id])
                   else
                     @shop.default_whatsapp_account
                   end
        render(json: { error: 'no WhatsApp account connected' }, status: :not_found) unless @account
      end
    end
  end
end
