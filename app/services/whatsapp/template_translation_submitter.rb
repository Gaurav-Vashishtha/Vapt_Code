# frozen_string_literal: true

module Whatsapp
  # Submits a reviewed translation to MSG91 (Meta review) under the English template's name.
  class TemplateTranslationSubmitter
    Result = Struct.new(:ok, :errors, keyword_init: true)

    def initialize(client: Msg91::WhatsappTemplateClient.new)
      @client = client
    end

    def call(translation, submitted_by:)
      return Result.new(ok: false, errors: ["Already #{translation.status}."]) unless translation.editable?

      authentication = translation.category.to_s.casecmp?("AUTHENTICATION")
      if authentication
        # Meta supplies the wording in the target language; the drafted text is only for reference.
        payload_components = TemplateComponents.authentication_payload(translation.source_components)
      else
        problems = TemplateTranslationValidator.errors(translation.source_components, translation.components)
        return Result.new(ok: false, errors: problems) if problems.any?

        payload_components = upload_media_samples(TemplateComponents.for_submission(translation.components))
      end
      response = @client.create(
        template_name: translation.template_name,
        language: translation.language,
        category: translation.category.presence || "UTILITY",
        components: payload_components
      )
      translation.update!(status: "submitted", submitted_at: Time.current, submitted_by: submitted_by,
                          rejection_reason: nil, last_msg91_response: response.is_a?(Hash) ? response : { "body" => response })
      Result.new(ok: true, errors: [])
    rescue Msg91::WhatsappTemplateClient::Error => e
      Rails.logger.error("[wa_translation] MSG91 create failed template=#{translation.template_name} " \
                         "lang=#{translation.language} components=#{payload_components.to_json}")
      translation.update!(status: "failed", rejection_reason: e.message,
                          last_msg91_response: e.response.is_a?(Hash) ? e.response : { "body" => e.response.to_s })
      Result.new(ok: false, errors: ["#{e.message}: #{e.response.to_json.first(300)}"])
    end

    private

    MEDIA_MAX_BYTES = 16 * 1024 * 1024
    MEDIA_EXTENSIONS = { "image/png" => ".png", "image/jpeg" => ".jpg", "video/mp4" => ".mp4",
                         "application/pdf" => ".pdf" }.freeze

    # Media headers carry a public sample URL from for_submission; Meta only accepts an upload
    # handle, so download each one and swap in the handle MSG91's sample-media-upload returns.
    def upload_media_samples(components)
      components.map do |c|
        url = c.dig("example", "header_handle")&.first
        next c unless c["type"] == "HEADER" && url.to_s.start_with?("http")

        c.merge("example" => { "header_handle" => [upload_sample(url)] })
      end
    end

    def upload_sample(url)
      response = HTTParty.get(url, timeout: 30, follow_redirects: true)
      unless response.success? && response.body.present?
        raise Msg91::WhatsappTemplateClient::Error.new("Sample media download failed (HTTP #{response.code})", { "url" => url })
      end
      if response.body.bytesize > MEDIA_MAX_BYTES
        raise Msg91::WhatsappTemplateClient::Error.new("Sample media is too large", { "url" => url })
      end

      content_type = response.headers["content-type"].to_s.split(";").first.to_s.strip.downcase
      ext = MEDIA_EXTENSIONS[content_type] || File.extname(URI.parse(url).path).presence || ".png"
      Tempfile.create(["wa_sample", ext], binmode: true) do |file|
        file.write(response.body)
        file.flush
        @client.upload_sample_media(file.path, content_type: content_type)
      end
    end
  end
end
