# frozen_string_literal: true

module Whatsapp
  module Inbox
    module MessageSerializer
      PREVIEW_LENGTH = 80

      module_function

      def list(messages, conversation:, current_agent: nil)
        messages = Array(messages)
        return [] if messages.empty?

        shop_id = conversation.shop_id
        agents = load_agents(messages, shop_id)
        logs = load_logs(messages, shop_id)
        campaign_names = load_campaign_names(messages, logs, shop_id)
        replies = load_reply_targets(messages, conversation)

        messages.map do |m|
          one(m, agents: agents, logs: logs, campaign_names: campaign_names, replies: replies, current_agent: current_agent)
        end
      end

      def one(message, agents:, logs:, campaign_names:, replies:, current_agent: nil)
        content = message.content.is_a?(Hash) ? message.content : {}
        {
          'id' => message.id,
          'direction' => message.direction,
          'source' => message.source,
          'kind' => message.kind,
          'meta_message_id' => message.meta_message_id,
          'body' => message.body,
          'content' => content,
          'media' => media_json(message),
          'reply_to' => replies[message.reply_to_meta_message_id],
          'status' => message.outbound? ? message.status : nil,
          'error' => error_json(message),
          'agent' => ConversationSerializer.agent_json(agents[message.agent_id], current_agent),
          'context' => context_json(message, content, logs[message.whatsapp_message_log_id], campaign_names),
          'occurred_at' => message.occurred_at,
          'updated_at' => message.updated_at
        }
      end

      def media_json(message)
        return nil unless WhatsappConversationMessage::MEDIA_KINDS.include?(message.kind.to_s)

        {
          'url' => media_url(message),
          'mime_type' => message.media_mime_type,
          'file_name' => message.media_file_name,
          'size' => message.media_size,
          'state' => message.media_state
        }
      end

      def media_url(message)
        ::Whatsapp::Inbox::MediaStore.url_for(message)
      rescue StandardError => e
        Rails.logger.warn("[Whatsapp::Inbox::MessageSerializer] media url msg=#{message.id} #{e.class}: #{e.message}")
        nil
      end

      def error_json(message)
        return nil if message.error_code.blank? && message.error_message.blank?

        { 'code' => message.error_code, 'message' => message.error_message }
      end

      def context_json(message, content, log, campaign_names)
        return nil unless message.kind.to_s == 'template' || log

        campaign_id = log&.dig(:campaign_id) || content['campaign_id']
        event_key = log&.dig(:event_type_key) || content['event_type_key']
        {
          'campaign_name' => campaign_id ? campaign_names[campaign_id.to_i] : nil,
          'event_label' => event_key.present? ? ::Whatsapp::EventRegistry.find(event_key)&.dig(:label) : nil,
          'template_name' => log&.dig(:template_name) || content['template_name']
        }
      end

      def load_agents(messages, shop_id)
        ids = messages.map(&:agent_id).compact.uniq
        return {} if ids.empty?

        WhatsappInboxAgent.where(shop_id: shop_id, id: ids).index_by(&:id)
      end

      def load_logs(messages, shop_id)
        ids = messages.map(&:whatsapp_message_log_id).compact.uniq
        return {} if ids.empty?

        WhatsappMessageLog.where(shop_id: shop_id, id: ids)
                          .pluck(:id, :whatsapp_campaign_id, :event_type_key, :template_name)
                          .to_h { |id, cid, key, name| [id, { campaign_id: cid, event_type_key: key, template_name: name }] }
      end

      def load_campaign_names(messages, logs, shop_id)
        ids = logs.values.filter_map { |l| l[:campaign_id] }
        ids += messages.filter_map { |m| m.content.is_a?(Hash) ? m.content['campaign_id'] : nil }
        ids = ids.map(&:to_i).select(&:positive?).uniq
        return {} if ids.empty?

        WhatsappCampaign.where(shop_id: shop_id, id: ids).pluck(:id, :name).to_h
      end

      def load_reply_targets(messages, conversation)
        wamids = messages.map(&:reply_to_meta_message_id).compact.uniq
        return {} if wamids.empty?

        WhatsappConversationMessage
          .where(whatsapp_conversation_id: conversation.id, meta_message_id: wamids)
          .pluck(:meta_message_id, :id, :body, :kind)
          .to_h { |wamid, id, body, kind| [wamid, { 'id' => id, 'preview' => preview(body, kind) }] }
      end

      def preview(body, kind)
        text = body.to_s.squish
        text.present? ? text.truncate(PREVIEW_LENGTH) : kind.to_s
      end
    end
  end
end
