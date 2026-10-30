# frozen_string_literal: true

module Whatsapp
  # Checks a translation against its English source before it can be submitted to Meta. Returns a
  # list of human-readable problems (empty when the translation is fine).
  module TemplateTranslationValidator
    module_function

    C = TemplateComponents

    def errors(source_components, components)
      source = C.normalize(source_components)
      target = C.normalize(components)
      return ["English source is missing — fetch from MSG91 first."] if source.empty?
      return ["Translation is empty."] if target.empty?

      problems = []
      if source.map { |c| c["type"] } != target.map { |c| c["type"] }
        problems << "Sections must match the English template (#{source.map { |c| c['type'] }.join(', ')})."
      end

      %w[HEADER BODY FOOTER].each do |type|
        src = C.find(source, type)
        tgt = C.find(target, type)
        next unless src

        if tgt.nil?
          problems << "#{type.capitalize} is missing."
          next
        end
        problems << "#{type.capitalize} format must stay #{src['format']}." if src["format"].to_s != tgt["format"].to_s
        next if src["text"].blank?

        text = tgt["text"].to_s.strip
        problems << "#{type.capitalize} text is empty." if text.empty?
        if C.placeholders(src["text"]) != C.placeholders(text)
          problems << "#{type.capitalize} must keep exactly the variables #{C.placeholders(src['text']).map { |n| "{{#{n}}}" }.join(' ')}."
        end
        limit = C::LIMITS[type]
        problems << "#{type.capitalize} is #{text.length} characters (max #{limit})." if limit && text.length > limit
        if type == "BODY" && C.edge_variable?(text)
          problems << "Body can't start or end with a variable — punctuation doesn't count, add a word before/after it (Meta rejects it)."
        end
      end

      src_buttons = C.buttons(source)
      tgt_buttons = C.buttons(target)
      if src_buttons.size != tgt_buttons.size
        problems << "Keep the same #{src_buttons.size} button(s)."
      else
        src_buttons.zip(tgt_buttons).each_with_index do |(s, t), i|
          label = "Button #{i + 1}"
          problems << "#{label} type must stay #{s['type']}." if s["type"].to_s.upcase != t["type"].to_s.upcase
          problems << "#{label} URL must not change." if s["url"].to_s != t["url"].to_s
          problems << "#{label} phone number must not change." if s["phone_number"].to_s != t["phone_number"].to_s
          problems << "#{label} text is empty." if s["text"].present? && t["text"].to_s.strip.empty?
          if t["text"].to_s.length > C::LIMITS["BUTTON"]
            problems << "#{label} text is #{t['text'].to_s.length} characters (max #{C::LIMITS['BUTTON']})."
          end
        end
      end

      problems.uniq
    end
  end
end
