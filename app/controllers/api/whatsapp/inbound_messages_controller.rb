module Api
  module Whatsapp
    class InboundMessagesController < AuthenticatedController
      PER_PAGE = 50
      DAY_OPTIONS = [1, 7, 30, 90].freeze
      KINDS = %w[button interactive text other].freeze

      def index
        page = [params[:page].to_i, 1].max
        days = DAY_OPTIONS.include?(params[:days].to_i) ? params[:days].to_i : 30

        scope = WhatsappInboundMessage
                .where(shop_id: @shop.id)
                .where('whatsapp_inbound_messages.received_at >= ?', days.days.ago)
                .from_source(params[:source])
                .matching(params[:q])
        kind = params[:kind].to_s
        scope = kind == 'button' ? scope.button_taps : scope.where(kind: kind) if KINDS.include?(kind)

        total = scope.count
        messages = scope.recent
                        .includes(:whatsapp_message_log)
                        .offset((page - 1) * PER_PAGE)
                        .limit(PER_PAGE)
                        .to_a

        render json: {
          messages: serialize_all(messages),
          total: total,
          page: page,
          per_page: PER_PAGE,
          days: days
        }
      end

      private

      def serialize_all(messages)
        normalized = messages.to_h { |m| [m.id, normalize(m.from_phone)] }
        phones = normalized.values.compact.uniq
        contact_names = WhatsappContact.where(shop_id: @shop.id, phone: phones).pluck(:phone, :name).to_h
        opted_out = WhatsappOptOut.opted_out_set(@shop.id)
        campaign_ids = messages.filter_map { |m| m.whatsapp_message_log&.whatsapp_campaign_id }.uniq
        campaign_names = campaign_ids.any? ? WhatsappCampaign.where(shop_id: @shop.id, id: campaign_ids).pluck(:id, :name).to_h : {}

        messages.map do |m|
          phone = normalized[m.id]
          {
            id: m.id,
            from_phone: m.from_phone,
            contact_name: phone && contact_names[phone].presence,
            display_text: m.display_text,
            kind: m.kind,
            received_at: m.received_at,
            opted_out: phone.present? && opted_out.include?(phone),
            context: context_for(m.whatsapp_message_log, campaign_names),
            wa_link: phone.present? ? "https://wa.me/#{phone}" : nil
          }
        end
      end

      def context_for(log, campaign_names)
        return { type: 'direct' } unless log

        if log.whatsapp_campaign_id
          {
            type: 'campaign',
            campaign_id: log.whatsapp_campaign_id,
            campaign_name: campaign_names[log.whatsapp_campaign_id],
            event_type_key: log.event_type_key,
            template_name: log.template_name
          }
        else
          {
            type: 'notification',
            event_type_key: log.event_type_key,
            event_label: ::Whatsapp::EventRegistry.find(log.event_type_key)&.dig(:label),
            template_name: log.template_name
          }
        end
      end

      def normalize(raw)
        WhatsappContact.normalize_phone(raw) || raw.to_s.gsub(/\D/, '').presence
      end
    end
  end
end
