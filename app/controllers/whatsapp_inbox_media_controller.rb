# frozen_string_literal: true

# Loaded by <img>/<audio> tags inside the embedded app, which cannot attach a
# session token, so access is granted by the short-lived signed token alone.
class WhatsappInboxMediaController < ActionController::Base
  INLINE_TYPES = %r{\A(image/(jpeg|png|gif|webp)|video/(mp4|3gpp)|audio/[a-z0-9.+-]+|application/pdf)\z}

  def show
    message_id = Whatsapp::Inbox::MediaStore.message_id_for(params[:token])
    message = message_id && WhatsappConversationMessage.find_by(id: message_id)
    return head :not_found if message.nil? || message.media_purged?

    if message.media_stored? && message.media_file.attached?
      return serve_stored(message)
    end
    return head :gone if message.media_id.blank?

    data = Whatsapp::Inbox::MediaFetcher.stream(message)
    render_bytes(data[:bytes], message.media_mime_type.presence || data[:mime_type], message)
  rescue Whatsapp::Inbox::MediaFetcher::Expired
    head :gone
  rescue Whatsapp::Inbox::MediaFetcher::Error => e
    Rails.logger.warn("[WhatsappInboxMediaController] message=#{message_id} #{e.class}: #{e.message}")
    head :bad_gateway
  end

  private

  def serve_stored(message)
    if Whatsapp::Inbox::MediaStore.s3?
      redirect_to message.media_file.url(expires_in: 10.minutes, disposition: :inline), allow_other_host: true
    else
      render_bytes(message.media_file.download, message.media_file.content_type, message)
    end
  end

  # Customer-sent files are untrusted: anything that is not a plain media type
  # is downloaded with a sandboxing CSP instead of rendered on our origin.
  def render_bytes(bytes, mime, message)
    mime = mime.to_s.split(';').first.to_s.strip.downcase
    inline = mime.match?(INLINE_TYPES)
    response.headers['Cache-Control'] = 'private, max-age=600'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Content-Security-Policy'] = "default-src 'none'; sandbox" unless inline
    send_data bytes,
              type: inline ? mime : 'application/octet-stream',
              disposition: inline ? 'inline' : 'attachment',
              filename: message.media_file_name.presence || "#{message.kind}-#{message.id}"
  end
end
