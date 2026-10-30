# frozen_string_literal: true

module MerchantWhatsapp
  module TemplateSync
    module_function

    def call
      account = OwnerWhatsappAccount.current
      raise "Owner sender is not configured" if account.nil? || account.waba_id.blank?
      raise "Owner sender has no system user token" if account.system_user_token.blank?

      response = account.graph_client.get(
        "#{account.waba_id}/message_templates",
        query: { fields: "id,name,language,category,status,components", limit: 200 }
      )

      Array(response["data"]).each do |t|
        record = OwnerWhatsappTemplate.find_or_initialize_by(name: t["name"], language: t["language"])
        record.assign_attributes(
          meta_template_id: t["id"],
          category: t["category"],
          status: map_status(t["status"]),
          header_text: component_header(t["components"]),
          body_text: component_body(t["components"]),
          buttons: component_buttons(t["components"])
        )
        record.variable_mapping = {} if record.variable_mapping.blank?
        record.save!
      end.size
    end

    def component_header(components)
      header = Array(components).find { |c| c.is_a?(Hash) && c["type"].to_s.casecmp?("HEADER") }
      return nil unless header

      format = header["format"].to_s.upcase
      format.blank? || format == "TEXT" ? header["text"] : "[#{format} header]"
    end

    def component_body(components)
      body = Array(components).find { |c| c.is_a?(Hash) && c["type"].to_s.casecmp?("BODY") }
      body && body["text"]
    end

    def component_buttons(components)
      btns = Array(components).find { |c| c.is_a?(Hash) && c["type"].to_s.casecmp?("BUTTONS") }
      Array(btns && btns["buttons"])
    end

    def map_status(status)
      status.to_s.downcase.presence || "pending"
    end
  end
end
