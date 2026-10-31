# frozen_string_literal: true

module Whatsapp
  # Helpers over MSG91 / Meta template components ([{ "type" => "BODY", "text" => ... }, ...]).
  module TemplateComponents
    module_function

    PLACEHOLDER = /\{\{\s*(\d+)\s*\}\}/
    LIMITS = { "HEADER" => 60, "BODY" => 1024, "FOOTER" => 60, "BUTTON" => 25 }.freeze

    def normalize(components)
      Array(components).filter_map do |c|
        next unless c.is_a?(Hash)

        c = c.deep_stringify_keys
        c["type"] = c["type"].to_s.upcase
        c["format"] = c["format"].to_s.upcase if c["format"].present?
        c["buttons"] = Array(c["buttons"]).select { |b| b.is_a?(Hash) }.map(&:deep_stringify_keys) if c.key?("buttons")
        c
      end
    end

    def find(components, type)
      normalize(components).find { |c| c["type"] == type }
    end

    def text_of(components, type)
      find(components, type)&.dig("text").to_s
    end

    def placeholders(text)
      text.to_s.scan(PLACEHOLDER).flatten.map(&:to_i).sort
    end

    # Meta/MSG91 reject a body whose first or last *word* is a variable. Whitespace, punctuation and
    # emoji around it don't count ("فريق {{4}} ." still ends with {{4}}), so strip them first.
    def edge_variable?(text)
      core = text.to_s.gsub(/\A[^\p{L}\p{N}{]+/, "").gsub(/[^\p{L}\p{N}}]+\z/, "")
      core.match?(/\A\{\{\s*\d+\s*\}\}/) || core.match?(/\{\{\s*\d+\s*\}\}\z/)
    end

    def buttons(components)
      Array(find(components, "BUTTONS")&.dig("buttons"))
    end

    # Translatable strings with stable ids: header (text headers only), body, footer, button labels.
    def translatable(components)
      list = []
      header = find(components, "HEADER")
      list << { "id" => "header", "text" => header["text"] } if header && header["format"].in?([nil, "", "TEXT"]) && header["text"].present?
      body = find(components, "BODY")
      list << { "id" => "body", "text" => body["text"] } if body && body["text"].present?
      footer = find(components, "FOOTER")
      list << { "id" => "footer", "text" => footer["text"] } if footer && footer["text"].present?
      buttons(components).each_with_index do |b, i|
        list << { "id" => "button_#{i}", "text" => b["text"] } if b["text"].present?
      end
      list
    end

    # Copy of `components` with translated strings put back by id; everything else (formats, URLs,
    # examples, button types) stays exactly as in the source.
    def apply(components, translations)
      by_id = translations.to_h { |t| [t["id"].to_s, t["text"].to_s] }
      normalize(components).map do |c|
        c = c.deep_dup
        case c["type"]
        when "HEADER" then c["text"] = by_id["header"] if by_id.key?("header") && c["text"].present?
        when "BODY" then c["text"] = by_id["body"] if by_id.key?("body")
        when "FOOTER" then c["text"] = by_id["footer"] if by_id.key?("footer")
        when "BUTTONS"
          c["buttons"] = c["buttons"].each_with_index.map do |b, i|
            by_id.key?("button_#{i}") ? b.merge("text" => by_id["button_#{i}"]) : b
          end
        end
        c
      end
    end

    # Sample image Meta needs for an IMAGE header. Override with WHATSAPP_TEMPLATE_SAMPLE_MEDIA_URL
    # (a real product photo is best for review).
    DEFAULT_SAMPLE_IMAGE_URL = "https://cdn.shopify.com/s/files/1/0655/2089/4070/files/whatsapp_abandon_preview.png?v=1774873052"

    # Meta's signed CDN links (what MSG91 hands back for an approved template's header) expire within
    # days, and Meta upload handles ("4::...") only work on Meta's own API — neither is a usable
    # sample for MSG91, which then rejects the IMAGE header as having no example.
    META_SIGNED_HOSTS = /(^|\.)(whatsapp\.net|fbcdn\.net|fbsbx\.com|facebook\.com)\z/i

    def usable_sample_url?(value)
      return false unless value.is_a?(String) && value.start_with?("http")

      host = URI.parse(value).host.to_s
      host.present? && !host.match?(META_SIGNED_HOSTS)
    rescue URI::InvalidURIError
      false
    end

    # A media header's sample: a stable URL the source carried (MSG91 has returned it under several
    # keys), else the configured / default sample image (IMAGE headers only).
    def media_sample(component)
      example = component["example"].is_a?(Hash) ? component["example"] : {}
      found = [example["header_handle"], example["header_url"], component["header_url"], component["image_url"]]
              .flat_map { |v| Array(v) }.find { |v| usable_sample_url?(v) }
      return found if found
      return ENV.fetch("WHATSAPP_TEMPLATE_SAMPLE_MEDIA_URL", nil).presence || DEFAULT_SAMPLE_IMAGE_URL if component["format"] == "IMAGE"

      ENV.fetch("WHATSAPP_TEMPLATE_SAMPLE_MEDIA_URL", nil).presence
    end

    # Authentication (OTP) templates can't carry custom text: Meta writes the body in every language
    # itself. Submitting the template's structure under a new language code makes Meta add its own
    # wording for that language. Verified against MSG91 client-panel-template.
    def authentication_payload(source_components)
      body = find(source_components, "BODY") || {}
      footer = find(source_components, "FOOTER")
      button = buttons(source_components).first || {}
      otp_type = button["otp_type"].presence ||
                 button["url"].to_s[/otp_type=([A-Z_]+)/, 1].presence || "COPY_CODE"

      payload = [{ "type" => "BODY", "add_security_recommendation" => body["add_security_recommendation"] != false }]
      if footer && footer["code_expiration_minutes"].present?
        payload << { "type" => "FOOTER", "code_expiration_minutes" => footer["code_expiration_minutes"].to_i }
      end
      payload << { "type" => "BUTTONS", "buttons" => [{ "type" => "OTP", "otp_type" => otp_type }] }
      payload
    end

    # Payload components for MSG91 create: known keys only, with sample values Meta requires for
    # every variable when the source carried none.
    def for_submission(components)
      normalize(components).map do |c|
        out = c.slice("type", "format", "text", "example", "buttons")
        case c["type"]
        when "BODY"
          count = placeholders(c["text"]).uniq.size
          if count.positive? && out.dig("example", "body_text").blank?
            out["example"] = { "body_text" => [Array.new(count) { |i| "Sample #{i + 1}" }] }
          end
        when "HEADER"
          if out["format"].in?([nil, "", "TEXT"]) && placeholders(out["text"]).any? && out.dig("example", "header_text").blank?
            out["example"] = { "header_text" => ["Sample"] }
          end
          # Always rebuild the media sample from a stable public URL. This is a placeholder:
          # TemplateTranslationSubmitter uploads it (MSG91 sample-media-upload) and swaps in the
          # Meta handle, because MSG91 passes header_handle to Meta untouched and Meta rejects URLs.
          if out["format"].in?(%w[IMAGE VIDEO DOCUMENT])
            out.delete("text")
            sample = media_sample(c)
            if sample
              out["example"] = { "header_handle" => [sample] }
            else
              out.delete("example")
            end
          end
        when "BUTTONS"
          out["buttons"] = c["buttons"].map do |b|
            button = b.slice("type", "text", "url", "phone_number", "example")
            if button["type"].to_s.upcase == "URL" && button["url"].to_s.match?(PLACEHOLDER) && button["example"].blank?
              button["example"] = [button["url"].gsub(PLACEHOLDER, "sample123")]
            end
            button
          end
        end
        out.compact
      end
    end
  end
end
