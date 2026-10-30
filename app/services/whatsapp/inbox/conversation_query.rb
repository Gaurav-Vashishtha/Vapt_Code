# frozen_string_literal: true

module Whatsapp
  module Inbox
    class ConversationQuery
      PAGE_SIZE = 30
      STATUSES = %w[open pending resolved].freeze
      MIN_PHONE_DIGITS = 4
      MAX_QUERY_LENGTH = 100

      def self.call(shop:, agent:, params:)
        new(shop, agent, params).call
      end

      def self.encode_cursor(time, id)
        return nil if time.nil? || id.nil?

        "#{time.to_i}.#{format('%06d', time.usec)}_#{id}"
      end

      def self.decode_cursor(raw)
        match = raw.to_s.match(/\A(\d{1,12}(?:\.\d{1,9})?)_(\d+)\z/)
        return nil unless match

        [Time.zone.at(Rational(match[1])), match[2].to_i]
      end

      def initialize(shop, agent, params)
        @shop = shop
        @agent = agent
        @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
        @params = @params.with_indifferent_access
      end

      def call
        filtered = apply_filters(base)
        page = apply_cursor(apply_status(filtered))
               .order(last_inbound_at: :desc, id: :desc)
               .limit(PAGE_SIZE + 1)
               .to_a
        more = page.size > PAGE_SIZE
        page = page.first(PAGE_SIZE)
        {
          conversations: page,
          next_cursor: more ? self.class.encode_cursor(page.last.last_inbound_at, page.last.id) : nil,
          counts: counts(filtered)
        }
      end

      private

      def base
        WhatsappConversation.where(shop_id: @shop.id)
      end

      def status
        value = @params[:status].to_s
        return value if STATUSES.include?(value) || value == 'all'

        'open'
      end

      def apply_status(scope)
        status == 'all' ? scope : scope.where(status: status)
      end

      def apply_filters(scope)
        scope = apply_assignee(scope)
        scope = apply_label(scope)
        scope = scope.where(whatsapp_account_id: @params[:account_id].to_i) if @params[:account_id].to_s.match?(/\A\d+\z/)
        scope = scope.where('whatsapp_conversations.unread_count > 0') if truthy?(@params[:unread])
        apply_search(scope)
      end

      def apply_assignee(scope)
        value = @params[:assignee].to_s
        case value
        when 'me'
          @agent&.id ? scope.where(assignee_agent_id: @agent.id) : scope.none
        when 'unassigned'
          scope.where(assignee_agent_id: nil)
        when /\A\d+\z/
          scope.where(assignee_agent_id: value.to_i)
        else
          scope
        end
      end

      def apply_label(scope)
        return scope unless @params[:label_id].to_s.match?(/\A\d+\z/)

        conversation_ids = WhatsappConversationLabel
                           .where(shop_id: @shop.id, whatsapp_inbox_label_id: @params[:label_id].to_i)
                           .select(:whatsapp_conversation_id)
        scope.where(id: conversation_ids)
      end

      def apply_search(scope)
        term = @params[:q].to_s.strip.first(MAX_QUERY_LENGTH)
        return scope if term.blank?

        clauses = []
        binds = []
        digits = term.gsub(/\D/, '').sub(/\A0+/, '')
        if digits.length >= MIN_PHONE_DIGITS && term.match?(/\A[\d\s+\-().#]+\z/)
          clauses << 'whatsapp_conversations.customer_wa_id LIKE ?'
          binds << "%#{digits}%"
        end
        if term.match?(/\p{L}/)
          clauses << 'whatsapp_conversations.customer_name ILIKE ?'
          binds << "%#{WhatsappConversation.sanitize_sql_like(term)}%"
        end
        if term.match?(/\A#?\s*\d+\z/)
          last10s = OrderLookup.find_by_order_number(@shop, term)
          if last10s.any?
            clauses << 'whatsapp_conversations.phone_last10 IN (?)'
            binds << last10s
          end
        end
        return scope.none if clauses.empty?

        scope.where(clauses.map { |c| "(#{c})" }.join(' OR '), *binds)
      end

      def apply_cursor(scope)
        cursor = self.class.decode_cursor(@params[:cursor])
        return scope unless cursor

        scope.where('(whatsapp_conversations.last_inbound_at, whatsapp_conversations.id) < (?, ?)', cursor[0], cursor[1])
      end

      def counts(filtered)
        by_status = filtered.unscope(:order).group(:status).count.transform_keys do |k|
          k.is_a?(Integer) ? WhatsappConversation.statuses.key(k) : k.to_s
        end
        {
          'open' => by_status.fetch('open', 0),
          'pending' => by_status.fetch('pending', 0),
          'resolved' => by_status.fetch('resolved', 0),
          'unread' => filtered.where('whatsapp_conversations.unread_count > 0').count
        }
      end

      def truthy?(value)
        ActiveModel::Type::Boolean.new.cast(value.presence) == true
      end
    end
  end
end
