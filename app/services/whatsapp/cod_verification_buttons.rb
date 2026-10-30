module Whatsapp
  module CodVerificationButtons
    CONFIRM = 'cod_confirm'.freeze
    CANCEL = 'cod_cancel'.freeze

    CANCEL_PATTERNS = [
      /cancel/, /\bannul/, /storn/, /\biptal/, /\bno\b/, /\bnahi\b/, /\bnahin\b/, /don'?t want/,
      /रद्द/, /कैंसल/, /नहीं/, /منسوخ/, /إلغاء/, /الغاء/, /取消/, /キャンセル/, /취소/, /отмен/
    ].freeze

    CONFIRM_PATTERNS = [
      /confirm/, /bestätig/, /\bonay/, /\bconferm/, /\byes\b/, /\bhaa?n\b/, /\bok\b/, /\bokay\b/,
      /place order/, /keep/, /पुष्टि/, /कन्फर्म/, /हाँ/, /हां/, /تصدیق/, /تأكيد/, /确认/, /確認/, /확인/, /подтверд/
    ].freeze

    module_function

    def classify(label)
      text = label.to_s.downcase.gsub(/[^\p{L}\p{M}\p{N}' ]+/, ' ').squeeze(' ').strip
      return nil if text.empty?

      cancel = CANCEL_PATTERNS.any? { |re| text.match?(re) }
      confirm = CONFIRM_PATTERNS.any? { |re| text.match?(re) }
      return nil if cancel == confirm

      cancel ? :cancel : :confirm
    end

    def quick_reply_buttons(components)
      buttons_component = Array(components).find do |c|
        c.is_a?(Hash) && fetch(c, 'type').to_s.casecmp?('BUTTONS')
      end
      return [] unless buttons_component

      Array(fetch(buttons_component, 'buttons')).each_with_index.filter_map do |b, index|
        next unless b.is_a?(Hash) && fetch(b, 'type').to_s.casecmp?('QUICK_REPLY')

        { index: index, text: fetch(b, 'text').to_s }
      end
    end

    def payload_params(components)
      quick_replies = quick_reply_buttons(components)
      intents = quick_replies.map { |qr| classify(qr[:text]) }

      if intents.count(:confirm) == 1 && intents.count(:cancel) == 1
        return quick_replies.zip(intents).filter_map do |qr, intent|
          next unless intent

          { 'index' => qr[:index], 'payload' => intent == :confirm ? CONFIRM : CANCEL }
        end
      end

      # Labels we can't read (another language/script) on a plain two-button
      # template: fall back to the documented Confirm-then-Cancel order.
      if quick_replies.size == 2 && intents.none?
        return [
          { 'index' => quick_replies[0][:index], 'payload' => CONFIRM },
          { 'index' => quick_replies[1][:index], 'payload' => CANCEL }
        ]
      end

      []
    end

    def payload_for_label(components, label)
      wanted = label.to_s.strip
      return nil if wanted.empty?

      by_index = payload_params(components).to_h { |p| [p['index'], p['payload']] }
      matches = quick_reply_buttons(components).select { |qr| qr[:text].strip.casecmp?(wanted) }
      payloads = matches.map { |qr| by_index[qr[:index]] }.uniq
      payloads.size == 1 ? payloads.first : nil
    end

    def mapping_error(components)
      quick_replies = quick_reply_buttons(components)
      if quick_replies.size < 2
        return 'COD verification templates need a Confirm and a Cancel quick-reply button.'
      end

      payloads = payload_params(components).map { |p| p['payload'] }
      return nil if payloads.include?(CONFIRM) && payloads.include?(CANCEL)

      labels = quick_replies.map { |qr| qr[:text] }.join(', ')
      "Couldn't tell which quick-reply button confirms and which cancels the order (#{labels}). " \
        "Use exactly one button labelled like \"Confirm\" and one labelled like \"Cancel\"."
    end

    def fetch(hash, key)
      hash.key?(key) ? hash[key] : hash[key.to_sym]
    end
  end
end
