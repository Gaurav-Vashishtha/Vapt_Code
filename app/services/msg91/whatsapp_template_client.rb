# frozen_string_literal: true

module Msg91
  # MSG91 WhatsApp template API for COD King's default number.
  #   GET  /api/v5/whatsapp/get-template-client/{number}   list templates (filter by name / status / language)
  #   POST /api/v5/whatsapp/client-panel-template/          create a template (one language)
  #   POST /api/v5/whatsapp/sample-media-upload/            upload a media header sample → Meta handle
  #
  # `templates` normalises the list response to one hash per template + language, because MSG91 has
  # returned it both grouped ({name, category, languages: [...]}) and flat ({name, language, ...}).
  class WhatsappTemplateClient
    BASE = "https://control.msg91.com/api/v5/whatsapp"
    TIMEOUT = 20

    class Error < StandardError
      attr_reader :response

      def initialize(message, response = nil)
        super(message)
        @response = response
      end
    end

    def initialize(authkey: ENV.fetch("MSG91_AUTHKEY", nil), number: ENV.fetch("WHATSAPP_NUMBER_DEFAULT", nil))
      @authkey = authkey
      @number = number.to_s.delete("+")
    end

    # => [{ name:, language:, status:, category:, components:, rejection_reason:, id: }]
    def templates(name: nil, language: nil, status: nil)
      raise Error, "MSG91_AUTHKEY / WHATSAPP_NUMBER_DEFAULT not set" if @authkey.blank? || @number.blank?

      query = { template_name: name, template_language: language, template_status: status }.compact
      response = HTTParty.get("#{BASE}/get-template-client/#{@number}", query: query, headers: headers, timeout: TIMEOUT)
      body = parsed(response)
      raise Error.new("MSG91 template list failed (HTTP #{response.code})", body) unless response.success? && !error_body?(body)

      self.class.normalize(body)
    end

    # payload: { template_name:, language:, category:, components: [...] } → parsed MSG91 response.
    def create(template_name:, language:, category:, components:)
      raise Error, "MSG91_AUTHKEY / WHATSAPP_NUMBER_DEFAULT not set" if @authkey.blank? || @number.blank?

      body = {
        integrated_number: @number,
        template_name: template_name,
        language: language,
        category: category.to_s.capitalize.presence || "Utility",
        button_url: false,
        components: components
      }
      response = HTTParty.post("#{BASE}/client-panel-template/", body: body.to_json, headers: headers, timeout: TIMEOUT)
      parsed_body = parsed(response)
      raise Error.new("MSG91 template create failed (HTTP #{response.code})", parsed_body) unless response.success? && !error_body?(parsed_body)

      parsed_body
    end

    # Uploads a media header sample and returns the Meta upload handle ("4:..."), which is what
    # example.header_handle must carry on create. A plain URL there is passed to Meta as-is and
    # rejected ("Templates with IMAGE header type need an example/sample").
    # Multipart fields: whatsapp_number + media (field name matters: "file" is rejected).
    def upload_sample_media(path, content_type:)
      raise Error, "MSG91_AUTHKEY / WHATSAPP_NUMBER_DEFAULT not set" if @authkey.blank? || @number.blank?

      response = File.open(path, "rb") do |file|
        HTTParty.post(
          "#{BASE}/sample-media-upload/",
          multipart: true,
          body: { whatsapp_number: @number, media: file },
          headers: { "authkey" => @authkey, "accept" => "application/json" },
          timeout: 60
        )
      end
      body = parsed(response)
      handle = body.is_a?(Hash) ? body.dig("data", "url").to_s : ""
      unless response.success? && !error_body?(body) && handle.present?
        raise Error.new("MSG91 sample media upload failed (HTTP #{response.code})", body)
      end

      handle
    end

    def self.normalize(body)
      rows = body.is_a?(Hash) ? (body["data"] || body["templates"] || []) : body
      Array(rows).flat_map do |tpl|
        next [] unless tpl.is_a?(Hash)

        languages = tpl["languages"]
        if languages.is_a?(Array)
          languages.filter_map { |lang| lang.is_a?(Hash) ? entry(tpl, lang) : nil }
        else
          [entry(tpl, tpl)]
        end
      end
    end

    def self.entry(tpl, lang)
      {
        name: (tpl["name"] || tpl["template_name"]).to_s,
        language: (lang["language"] || string_or_nil(lang["code"]) || tpl["language"]).to_s,
        status: (lang["status"] || tpl["status"]).to_s.downcase,
        category: (tpl["category"] || lang["category"]).to_s.upcase.presence,
        components: components_of(lang),
        rejection_reason: real_reason(lang["rejection_reason"] || lang["reason"]),
        id: (lang["id"] || tpl["id"]).to_s.presence
      }
    end

    # `code` is a language code in some responses and the component array in others.
    def self.string_or_nil(value)
      value.is_a?(String) ? value.presence : nil
    end

    # MSG91 reports "NONE" when nothing was rejected.
    def self.real_reason(value)
      text = value.to_s.strip
      text.empty? || text.casecmp?("none") ? nil : text
    end

    # Components live under `components`, or under `code` when `code` is the component array.
    def self.components_of(lang)
      list = lang["components"]
      list = lang["code"] if list.blank? && lang["code"].is_a?(Array)
      Array(list).select { |c| c.is_a?(Hash) }
    end

    private

    def headers
      { "authkey" => @authkey, "accept" => "application/json", "content-type" => "application/json" }
    end

    def parsed(response)
      response.parsed_response.is_a?(String) ? JSON.parse(response.body) : response.parsed_response
    rescue JSON::ParserError
      { "raw" => response.body.to_s.first(2000) }
    end

    def error_body?(body)
      body.is_a?(Hash) && (body["hasError"] == true || body["status"].to_s.casecmp?("fail") || body["status"].to_s.casecmp?("error"))
    end
  end
end

