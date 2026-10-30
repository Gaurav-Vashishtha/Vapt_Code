# frozen_string_literal: true

module MerchantWhatsapp
  module Sender
    module_function

    def call(template:, recipient:, body_parameters: [], header_parameters: nil, button_slug: nil, button_params: nil)
      account = OwnerWhatsappAccount.current
      raise "owner sender not ready" unless account&.ready_to_send?

      components = []
      components << { "type" => "header", "parameters" => header_parameters } if header_parameters.present?
      components << { "type" => "body", "parameters" => body_parameters } if body_parameters.present?
      components.concat(button_components(template, button_slug, button_params))

      body = {
        messaging_product: "whatsapp",
        to: normalize_phone(recipient),
        type: "template",
        template: { name: template.name, language: { code: template.language } }
      }
      body[:template][:components] = components if components.any?

      response = account.graph_client.post("#{account.phone_number_id}/messages", body: body)
      response.dig("messages", 0, "id")
    end

    # Meta rejects the send with 131008 unless EVERY dynamic URL button gets a
    # parameter. `button_params` ([{ index:, slug: }]) wins; a bare
    # `button_slug` (legacy callers, admin test button) is fanned out to all
    # of the template's dynamic URL buttons.
    def button_components(template, button_slug, button_params)
      params =
        if button_params.present?
          button_params
        elsif button_slug.present?
          indexes = template.respond_to?(:dynamic_url_button_indexes) ? template.dynamic_url_button_indexes : []
          indexes = [0] if indexes.empty?
          indexes.map { |i| { index: i, slug: button_slug } }
        else
          []
        end

      params.map do |bp|
        {
          "type" => "button",
          "sub_type" => "url",
          "index" => (bp[:index] || bp["index"]).to_i.to_s,
          "parameters" => [{ "type" => "text", "text" => (bp[:slug] || bp["slug"]).to_s }]
        }
      end
    end

    def normalize_phone(value)
      value.to_s.gsub(/\D/, "").sub(/\A0+/, "")
    end
  end
end
