# frozen_string_literal: true

module Whatsapp
  module Ai
    module KnowledgeImporter
      class Error < StandardError; end

      POLICY_LIMIT = 1500
      QUERY = <<~GRAPHQL
        query { shop { name shopPolicies { type title body } } }
      GRAPHQL

      module_function

      def call(shop, setting)
        data = ShopifyGraphql.call(shop, QUERY)
        policies = Array(data.dig('shop', 'shopPolicies')).select { |p| p['body'].present? }
        raise Error, 'No store policies found in Shopify. Paste your shipping and return details instead.' if policies.empty?

        sections = policies.map do |policy|
          text = ActionView::Base.full_sanitizer.sanitize(policy['body'].to_s).gsub(/[ \t]+/, ' ').gsub(/\n{3,}/, "\n\n").strip
          "#{policy['title'].presence || policy['type'].to_s.humanize}:\n#{text.truncate(POLICY_LIMIT)}"
        end
        merged = [setting.knowledge.to_s.strip.presence, *sections].compact.join("\n\n")
        merged.first(WhatsappAiSetting::MAX_KNOWLEDGE)
      rescue ShopifyGraphql::Error => e
        raise Error, "Couldn't read your store policies from Shopify (#{e.message}). Paste them instead."
      end
    end
  end
end
