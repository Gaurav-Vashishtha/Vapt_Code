# frozen_string_literal: true

module Whatsapp
  module Inbox
    # Meta inbound message shapes: https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks/payload-examples
    module InboundParser
      MEDIA_TYPES = %w[image video audio document sticker].freeze
      OUTSIDE_WINDOW_KINDS = %w[reaction system unsupported].freeze

      module_function

      def parse(msg)
        msg = msg.is_a?(Hash) ? msg.deep_stringify_keys : {}
        type = msg['type'].to_s
        result =
          if MEDIA_TYPES.include?(type)
            media(msg, type)
          else
            case type
            when 'text' then base('text', msg.dig('text', 'body'))
            when 'location' then location(msg)
            when 'contacts' then contacts(msg)
            when 'reaction' then reaction(msg)
            when 'button' then button(msg)
            when 'interactive' then interactive(msg)
            when 'order' then order(msg)
            when 'system' then base('system', msg.dig('system', 'body'), 'meta_type' => msg.dig('system', 'type').to_s.presence || 'system')
            else base('unsupported', nil, 'meta_type' => type.presence || 'unknown')
            end
          end

        referral = msg['referral']
        if referral.is_a?(Hash) && referral.any?
          result[:content] = result[:content].merge('referral' => referral.slice('source_url', 'source_type', 'source_id', 'headline', 'body', 'media_type'))
        end
        result[:reply_to_meta_message_id] = msg.dig('context', 'id').to_s.presence
        result[:counts_for_window] = !OUTSIDE_WINDOW_KINDS.include?(result[:kind])
        result
      end

      def base(kind, body, content = {})
        { kind: kind, body: body.to_s.presence, content: content, media: nil }
      end

      def media(msg, type)
        node = msg[type].is_a?(Hash) ? msg[type] : {}
        content = type == 'audio' ? { 'voice' => node['voice'] == true } : {}
        content['animated'] = node['animated'] == true if type == 'sticker'
        result = base(type, node['caption'], content)
        result[:media] = {
          id: node['id'].to_s.presence,
          mime_type: node['mime_type'].to_s.presence,
          file_name: node['filename'].to_s.presence,
          sha256: node['sha256'].to_s.presence,
          voice: node['voice'] == true
        }
        result[:media] = nil if result[:media][:id].nil?
        result
      end

      def location(msg)
        node = msg['location'].is_a?(Hash) ? msg['location'] : {}
        content = {
          'latitude' => node['latitude']&.to_f,
          'longitude' => node['longitude']&.to_f,
          'name' => node['name'].to_s.presence,
          'address' => node['address'].to_s.presence,
          'url' => node['url'].to_s.presence
        }
        base('location', content['name'] || content['address'], content)
      end

      def contacts(msg)
        list = Array(msg['contacts']).select { |c| c.is_a?(Hash) }.map do |c|
          name = c['name'].is_a?(Hash) ? c['name'] : {}
          {
            'name' => name['formatted_name'].presence || [name['first_name'], name['last_name']].compact.join(' ').presence,
            'phones' => Array(c['phones']).filter_map { |p| p.is_a?(Hash) ? (p['phone'].presence || p['wa_id'].presence) : nil }
          }
        end
        base('contacts', list.filter_map { |c| c['name'] }.join(', '), 'contacts' => list)
      end

      def reaction(msg)
        node = msg['reaction'].is_a?(Hash) ? msg['reaction'] : {}
        base('reaction', nil, 'emoji' => node['emoji'].to_s, 'target_meta_message_id' => node['message_id'].to_s.presence)
      end

      def button(msg)
        node = msg['button'].is_a?(Hash) ? msg['button'] : {}
        text = node['text'].to_s.presence || node['payload'].to_s
        base('button', text, 'payload' => node['payload'].to_s.presence || text, 'button_text' => text)
      end

      def interactive(msg)
        node = msg['interactive'].is_a?(Hash) ? msg['interactive'] : {}
        if node['type'].to_s == 'nfm_reply' || node['nfm_reply'].is_a?(Hash)
          nfm = node['nfm_reply'].is_a?(Hash) ? node['nfm_reply'] : {}
          return base('interactive', 'Form submitted',
                      'payload' => nfm['name'].to_s.presence || 'flow', 'button_text' => 'Form submitted',
                      'response_json' => nfm['response_json'].to_s.presence)
        end

        reply = node['button_reply'] || node['list_reply']
        reply = {} unless reply.is_a?(Hash)
        text = reply['title'].to_s.presence || reply['id'].to_s
        base('interactive', text, 'payload' => reply['id'].to_s, 'button_text' => text)
      end

      def order(msg)
        node = msg['order'].is_a?(Hash) ? msg['order'] : {}
        items = Array(node['product_items']).select { |i| i.is_a?(Hash) }
        base('order', 'Cart sent',
             'catalog_id' => node['catalog_id'].to_s.presence,
             'text' => node['text'].to_s.presence,
             'items_count' => items.sum { |i| i['quantity'].to_i })
      end
    end
  end
end
