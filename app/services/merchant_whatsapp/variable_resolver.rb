# frozen_string_literal: true

module MerchantWhatsapp
  module VariableResolver
    module_function

    def body_parameters(template, record, context = {}, mapping: nil)
      mapping = mapping.presence || template.variable_mapping || {}
      mapping.keys.map(&:to_i).sort.map do |pos|
        source = mapping[pos.to_s]
        { "type" => "text", "text" => resolve(source, record, context).to_s }
      end
    end

    def resolve(source, record, context)
      key = source.to_s
      return context[key].to_s if context.key?(key)
      return key.sub("literal:", "") if key.start_with?("literal:")
      return record.try(key.sub("shop.", "")).to_s if key.start_with?("shop.")

      case key
      when "store.name" then record.try(:shop_owner).presence || domain_of(record)
      when "owner.name" then record.try(:owner_name).presence || "there"
      when "domain" then domain_of(record)
      else ""
      end
    end

    def domain_of(record)
      (record.try(:shopify_domain) || record.try(:shop_domain)).to_s.sub(".myshopify.com", "")
    end
  end
end
