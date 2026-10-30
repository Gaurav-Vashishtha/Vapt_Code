# frozen_string_literal: true

module Whatsapp
  module Inbox
    module ConversationSerializer
      module_function

      def list(conversations, shop:, current_agent: nil)
        conversations = Array(conversations)
        return [] if conversations.empty?

        lookups = batch_lookups(conversations, shop)
        conversations.map { |c| one(c, current_agent: current_agent, **lookups) }
      end

      def detail(conversation, shop:, current_agent: nil)
        lookups = batch_lookups([conversation], shop)
        one(conversation, current_agent: current_agent, **lookups).merge(
          'note' => conversation.note,
          'status_changed_at' => conversation.status_changed_at,
          'episode' => episode_json(conversation),
          'variables' => variables_for(conversation),
          'ai' => ai_json(conversation, shop)
        )
      end

      def ai_json(conversation, shop)
        setting = WhatsappAiSetting.find_by(shop_id: shop.id)
        now = Time.current
        {
          'enabled' => setting.present? && setting.handles?(conversation) && ::Whatsapp::Ai::Config.enabled?,
          'mode' => setting&.status || 'off',
          'available' => setting.present? && !setting.agent_off? && ::Whatsapp::Ai::Config.enabled?,
          'paused' => conversation.ai_paused_until.present? && conversation.ai_paused_until > now,
          'handoff_at' => conversation.ai_handoff_at,
          'team_timeout_minutes' => setting&.team_timeout_minutes.to_i,
          'agent_quiet' => setting&.agent_live? == true && conversation.last_agent_reply_at.present? && conversation.last_agent_reply_at > now - ::Whatsapp::Ai::Responder::AGENT_QUIET,
          'draft' => conversation.ai_draft.presence,
          'draft_at' => conversation.ai_draft_at
        }
      rescue StandardError => e
        Rails.logger.error("[Whatsapp::Inbox::ConversationSerializer] ai conv=#{conversation.id} #{e.class}: #{e.message}")
        { 'enabled' => false, 'mode' => 'off' }
      end

      def one(conversation, labels_by_conv:, agents_by_id:, opted_out_set:, accounts_by_id: {}, current_agent: nil)
        account = accounts_by_id[conversation.whatsapp_account_id]
        {
          'id' => conversation.id,
          'status' => conversation.status,
          'customer' => {
            'name' => conversation.customer_name.presence,
            'wa_id' => conversation.customer_wa_id,
            'phone_display' => phone_display(conversation.customer_wa_id)
          },
          'account' => account && { 'id' => account.id, 'label' => account.display_label },
          'last_message' => {
            'direction' => conversation.last_message_direction,
            'preview' => conversation.last_message_preview,
            'at' => conversation.last_message_at
          },
          'last_inbound_at' => conversation.last_inbound_at,
          'window_expires_at' => conversation.window_expires_at,
          'window_open' => conversation.window_open?,
          'unread_count' => conversation.unread_count.to_i,
          'assignee' => agent_json(agents_by_id[conversation.assignee_agent_id], current_agent),
          'labels' => labels_by_conv.fetch(conversation.id, []),
          'opted_out' => opted_out?(conversation, opted_out_set)
        }
      end

      def agent_json(agent, current_agent = nil)
        return nil if agent.nil?

        {
          'id' => agent.id,
          'name' => agent_name(agent),
          'email' => agent.email.presence,
          'is_store_team' => agent.store_team?,
          'is_me' => current_agent.present? && agent.id.present? && agent.id == current_agent.id
        }
      end

      def agent_name(agent)
        return I18n.t('whatsapp_inbox.store_team', default: 'Store team') if agent.store_team? && agent.name.blank?

        agent.display_name
      end

      def phone_display(wa_id)
        digits = wa_id.to_s.gsub(/\D/, '')
        return wa_id.to_s if digits.length < 10
        return "+#{digits}" if digits.length == 10

        country = digits[0...-10]
        local = digits[-10..]
        "+#{country} #{local[0, 5]} #{local[5, 5]}"
      end

      def phone_keys(conversation)
        [conversation.customer_wa_id.to_s.gsub(/\D/, ''), conversation.phone_last10.to_s].reject(&:blank?).uniq
      end

      def opted_out?(conversation, opted_out_set)
        phone_keys(conversation).any? { |p| opted_out_set.include?(p) }
      end

      def batch_lookups(conversations, shop)
        ids = conversations.map(&:id)
        {
          labels_by_conv: labels_by_conversation(ids, shop),
          agents_by_id: agents_by_id(conversations.map(&:assignee_agent_id), shop),
          opted_out_set: opted_out_set(conversations, shop),
          accounts_by_id: accounts_by_id(conversations.map(&:whatsapp_account_id), shop)
        }
      end

      def labels_by_conversation(conversation_ids, shop)
        rows = WhatsappConversationLabel
               .where(shop_id: shop.id, whatsapp_conversation_id: conversation_ids)
               .pluck(:whatsapp_conversation_id, :whatsapp_inbox_label_id)
        return {} if rows.empty?

        labels = WhatsappInboxLabel.where(shop_id: shop.id, id: rows.map(&:last).uniq).ordered.to_a
        position = labels.each_with_index.to_h { |l, i| [l.id, i] }
        by_id = labels.index_by(&:id)
        rows.group_by(&:first).transform_values do |pairs|
          pairs.map(&:last).uniq.select { |id| by_id.key?(id) }.sort_by { |id| position[id] }.map { |id| by_id[id].as_inbox_json }
        end
      end

      def agents_by_id(ids, shop)
        ids = ids.compact.uniq
        return {} if ids.empty?

        WhatsappInboxAgent.where(shop_id: shop.id, id: ids).index_by(&:id)
      end

      def accounts_by_id(ids, shop)
        ids = ids.compact.uniq
        return {} if ids.empty?

        WhatsappAccount.where(shop_id: shop.id, id: ids).index_by(&:id)
      end

      def opted_out_set(conversations, shop)
        phones = conversations.flat_map { |c| phone_keys(c) }.uniq
        return Set.new if phones.empty?

        WhatsappOptOut.where(shop_id: shop.id, phone_normalized: phones).pluck(:phone_normalized).to_set
      end

      def episode_json(conversation)
        episode = conversation.current_episode_id && WhatsappConversationEpisode.find_by(
          id: conversation.current_episode_id, shop_id: conversation.shop_id
        )
        return nil unless episode

        { 'opened_at' => episode.opened_at, 'first_response_at' => episode.first_response_at }
      end

      def variables_for(conversation)
        ::Whatsapp::Inbox::ReplyVariables.values_for(conversation)
      rescue StandardError => e
        Rails.logger.error("[Whatsapp::Inbox::ConversationSerializer] variables conv=#{conversation.id} #{e.class}: #{e.message}")
        WhatsappInboxSetting::VARIABLES.index_with('')
      end
    end
  end
end
