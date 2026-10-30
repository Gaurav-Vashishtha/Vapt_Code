# frozen_string_literal: true

require "json"

module CodForm
  module Engine
    # Translates the English texts COD King puts in new records ("Buy with COD", "Buy more, save
    # more", "2 packs", "Most popular"…) into every language the storefront package ships
    # (config/cod_form/default_texts.json, generated from storefront/cod-form/src/i18n).
    #
    # A label map such as {"default" => "2 packs"} becomes
    # {"default" => "2 packs", "hi" => "2 पैक", "fr" => "2 lots", …}: the merchant's own entries are
    # never touched, and a text that is not one of the shipped English defaults is left alone.
    # Used for what Liquid and the product-page widgets resolve on their own (metafield, bundles).
    class DefaultLabels
      PATH = File.expand_path("../../../../config/cod_form/default_texts.json", __dir__)
      NUMBER_VARS = %w[count value seconds].freeze
      # Texts with a {variable} are matched only for these keys (a short pattern such as
      # "Order {order_name}" would otherwise swallow a merchant's own "Order now").
      PATTERN_KEYS = %w[tier_pack_one tier_pack_other downsell_title upsell_title thank_you_message
                        thank_you_whatsapp_message threshold_gift_progress threshold_ship_progress].freeze

      class << self
        def localize(map)
          return map unless map.is_a?(Hash)

          source = [map["default"], map["en"]].map { |text| text.to_s.strip }.find { |text| !text.empty? }
          return map if source.nil?

          found = match(source)
          return map unless found

          key, values = found
          out = map.dup
          texts.each do |locale, strings|
            next if locale == "en" || !out[locale].to_s.strip.empty?

            template = strings[key].to_s
            next if template.empty?

            out[locale] = template.gsub(/\{(\w+)\}/) { values.key?(Regexp.last_match(1)) ? values[Regexp.last_match(1)] : Regexp.last_match(0) }
          end
          out
        end

        # => [text key, {"var" => value}] when `text` is one of the English defaults, else nil.
        def match(text)
          wanted = text.to_s.strip.downcase
          return nil if wanted.empty?

          patterns.each do |key, regex, names|
            data = regex.match(wanted)
            next unless data

            original = text.to_s.strip
            values = {}
            names.each_with_index do |name, index|
              # Take the captured value from the original (not downcased) text.
              start, stop = data.offset(index + 1)
              values[name] = original[start...stop]
            end
            return [key, values]
          end
          nil
        end

        def texts
          @texts ||= begin
            data = JSON.parse(File.read(PATH, encoding: "UTF-8"))
            data.is_a?(Hash) ? data : {}
          rescue StandardError
            {}
          end
        end

        def reset!
          @texts = nil
          @patterns = nil
        end

        private

        def patterns
          @patterns ||= texts.fetch("en", {}).filter_map do |key, english|
            english = english.to_s.strip
            next if english.empty?
            next if english.include?("{") && !PATTERN_KEYS.include?(key)

            names = []
            source = english.downcase.split(/(\{\w+\})/).map do |part|
              if part.match?(/\A\{\w+\}\z/)
                name = part[1..-2]
                names << name
                NUMBER_VARS.include?(name) ? '(\d+(?:[.,]\d+)?|\{' + name + '\})' : '(.+?)'
              else
                Regexp.escape(part)
              end
            end.join
            [key, Regexp.new("\\A#{source}\\z"), names]
          end
        end
      end
    end
  end
end
