# frozen_string_literal: true

require "httparty"

module MerchantWhatsapp
  module TemplateBuilder
    module_function

    def create(attrs)
      account = OwnerWhatsappAccount.current
      raise "Owner sender is not configured" if account.nil? || account.waba_id.blank?
      raise "Owner sender has no system user token" if account.system_user_token.blank?

      name = attrs[:name].to_s.strip
      raise "Template name is required" if name.blank?
      raise "Body text is required" if attrs[:body].to_s.strip.blank?

      language = attrs[:language].presence || "en_US"
      category = attrs[:category].presence || "UTILITY"
      components = build_components(attrs)

      payload = { name: name, language: language, category: category, components: resolve_header_handles(account, components) }
      response = account.graph_client.post("#{account.waba_id}/message_templates", body: payload)

      record = OwnerWhatsappTemplate.find_or_initialize_by(name: name, language: language)
      record.assign_attributes(
        meta_template_id: response["id"],
        category: category,
        status: (response["status"] || "PENDING").to_s.downcase,
        header_text: header_display(attrs),
        body_text: attrs[:body].to_s,
        footer_text: attrs[:footer].presence,
        buttons: buttons_of(components),
        components: components
      )
      record.variable_mapping = attrs[:variable_mapping] if attrs[:variable_mapping].present?
      record.variable_mapping = {} if record.variable_mapping.blank?
      record.save!
      record
    end

    def build_components(attrs)
      comps = []
      header = header_component(attrs)
      comps << header if header
      comps << body_component(attrs)
      comps << { "type" => "FOOTER", "text" => attrs[:footer].to_s } if attrs[:footer].present?
      buttons = button_components(attrs[:buttons])
      comps << { "type" => "BUTTONS", "buttons" => buttons } if buttons.any?
      comps
    end

    def header_component(attrs)
      case attrs[:header_type].to_s
      when "text"
        return nil if attrs[:header_text].blank?

        comp = { "type" => "HEADER", "format" => "TEXT", "text" => attrs[:header_text].to_s }
        if attrs[:header_text].to_s.match?(/\{\{\d+\}\}/)
          comp["example"] = { "header_text" => [attrs[:header_sample].presence || "Sample"] }
        end
        comp
      when "image"
        return nil if attrs[:header_image_url].blank?

        { "type" => "HEADER", "format" => "IMAGE", "example" => { "header_handle" => [attrs[:header_image_url].to_s] } }
      end
    end

    # Meta rejects raw URLs in example.header_handle at template-create time
    # ("Missing sample parameter for title type") — it requires a Resumable
    # Upload API handle. The persisted record keeps the URL because handles are
    # invalid at send time, where image.link is used instead.
    def resolve_header_handles(account, components)
      components.map do |c|
        next c unless c["type"] == "HEADER" && %w[IMAGE VIDEO DOCUMENT].include?(c["format"].to_s)

        value = c.dig("example", "header_handle")&.first
        next c unless value.to_s.start_with?("http")

        handle = upload_url_for_handle(account, value, c["format"])
        c.merge("example" => c["example"].merge("header_handle" => [handle]))
      end
    end

    def upload_url_for_handle(account, url, format)
      resp = HTTParty.get(url, follow_redirects: true)
      raise "could not download header sample from #{url} (HTTP #{resp.code})" unless resp.success?

      default_mime = { "IMAGE" => "image/jpeg", "VIDEO" => "video/mp4", "DOCUMENT" => "application/pdf" }[format.to_s] || "application/octet-stream"
      mime = resp.headers["content-type"].to_s.split(";").first.presence || default_mime

      Meta::ResumableUploadService.call(
        account: account,
        bytes: resp.body.to_s.b,
        mime_type: mime,
        file_name: File.basename(URI.parse(url).path).presence || "header_sample"
      )
    rescue Meta::ResumableUploadService::Error => e
      raise "could not prepare header sample: #{e.message}"
    end

    def body_component(attrs)
      body = attrs[:body].to_s
      comp = { "type" => "BODY", "text" => body }
      positions = body.scan(/\{\{(\d+)\}\}/).flatten.map(&:to_i).uniq.sort
      if positions.any?
        samples = Array(attrs[:body_samples]).map(&:to_s)
        comp["example"] = { "body_text" => [positions.map { |n| samples[n - 1].presence || "Sample" }] }
      end
      comp
    end

    def button_components(buttons)
      Array(buttons).filter_map do |b|
        text = value_of(b, "text").to_s.strip
        next if text.blank?

        if value_of(b, "type").to_s == "URL"
          url = value_of(b, "url").to_s.strip
          next if url.blank?

          button = { "type" => "URL", "text" => text, "url" => url }
          button["example"] = [url.gsub(/\{\{\d+\}\}/, "sample.myshopify.com")] if url.include?("{{")
          button
        elsif value_of(b, "type").to_s == "QUICK_REPLY"
          { "type" => "QUICK_REPLY", "text" => text }
        end
      end
    end

    def buttons_of(components)
      comp = components.find { |c| c["type"] == "BUTTONS" }
      Array(comp && comp["buttons"])
    end

    def header_display(attrs)
      case attrs[:header_type].to_s
      when "text" then attrs[:header_text].to_s
      when "image" then "[IMAGE header]"
      end
    end

    def value_of(hash, key)
      return nil unless hash.respond_to?(:[])

      hash[key] || hash[key.to_sym]
    end
  end
end
