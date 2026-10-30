# frozen_string_literal: true

module Whatsapp
  module Inbox
    # Safe to re-run: inbound rows are matched by whatsapp_inbound_message_id,
    # logs by whatsapp_message_log_id, and only conversations that never had
    # an episode (created by this job) get their status computed.
    class BackfillShopJob < ApplicationJob
      sidekiq_options queue: 'low', retry: 1

      RESOLVE_AFTER = 72.hours
      MEDIA_MAX_AGE = 25.days

      def perform(shop_id)
        shop = Shop.find_by(id: shop_id)
        return if shop.nil? || InboundRecorder.disabled?

        conversation_ids = Set.new
        WhatsappInboundMessage.where(shop_id: shop.id).where.not(whatsapp_account_id: nil)
                              .includes(:whatsapp_account)
                              .find_each do |inbound|
          message = InboundRecorder.call(inbound, profile_name: nil, backfill: true)
          conversation_ids << message.whatsapp_conversation_id if message
        rescue StandardError => e
          Rails.logger.error("[Whatsapp::Inbox::BackfillShopJob] shop=#{shop.id} inbound=#{inbound.id} #{e.class}: #{e.message}")
        end

        WhatsappConversation.where(id: conversation_ids.to_a, current_episode_id: nil).find_each do |conversation|
          BackfillThreadJob.new.perform(conversation.id)
          finalize(conversation.reload)
          enqueue_media(conversation)
        rescue StandardError => e
          Rails.logger.error("[Whatsapp::Inbox::BackfillShopJob] shop=#{shop.id} conversation=#{conversation.id} #{e.class}: #{e.message}")
        end
      end

      private

      def finalize(conversation)
        messages = WhatsappConversationMessage.where(whatsapp_conversation_id: conversation.id)
        last_inbound_at = conversation.last_inbound_at
        last_outbound_before = messages.outbound.where('occurred_at <= ?', last_inbound_at).maximum(:occurred_at)
        stretch = messages.inbound.where.not(kind: InboundRecorder::NO_ATTENTION_KINDS)
        stretch = stretch.where('occurred_at > ?', last_outbound_before) if last_outbound_before
        opened_at = stretch.minimum(:occurred_at) || last_inbound_at
        resolved = last_inbound_at < RESOLVE_AFTER.ago
        replied_after = messages.outbound.where('occurred_at > ?', last_inbound_at).exists?

        WhatsappConversation.transaction do
          conversation.lock!
          next if conversation.current_episode_id.present?

          episode = WhatsappConversationEpisode.create!(
            whatsapp_conversation_id: conversation.id,
            shop_id: conversation.shop_id,
            opened_at: opened_at,
            resolved_at: resolved ? [last_inbound_at + RESOLVE_AFTER, Time.current].min : nil,
            resolved_by: resolved ? 'auto' : nil
          )
          conversation.update!(
            status: resolved ? 'resolved' : 'open',
            status_changed_at: resolved ? episode.resolved_at : opened_at,
            current_episode_id: episode.id,
            unread_count: !resolved && !replied_after ? 1 : 0
          )
        end
      end

      def enqueue_media(conversation)
        return unless MediaStore.enabled?

        WhatsappConversationMessage.where(whatsapp_conversation_id: conversation.id, media_state: :pending)
                                   .where('occurred_at > ?', MEDIA_MAX_AGE.ago)
                                   .pluck(:id).each_with_index do |id, i|
          DownloadMediaJob.perform_in(i * 2, id)
        end
      end
    end
  end
end
