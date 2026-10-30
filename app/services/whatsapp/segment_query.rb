module Whatsapp
  # Resolves a segment's jsonb filters into a WhatsappContact scope.
  # jsonb_exists_any/all are the function forms of the ?| / ?& operators —
  # the operators can't be used in Rails where() strings because ? is the
  # bind-parameter marker.
  module SegmentQuery
    module_function

    def scope(shop_id, filters)
      f = (filters || {}).to_h.stringify_keys
      s = WhatsappContact.where(shop_id: shop_id)
      s = s.subscribed unless truthy?(f['include_unsubscribed'])

      sources = Array(f['sources']) & WhatsappContact::SOURCES
      s = s.where(source: sources) if sources.any?

      s = tags_condition(s, f)
      s = created_condition(s, f)
      s = numeric_conditions(s, f)
      s = recency_conditions(s, f)
      cod_conditions(s, f)
    end

    def tags_condition(s, f)
      any = clean_tags(f['tags_any'])
      all = clean_tags(f['tags_all'])
      none = clean_tags(f['tags_none'])
      s = s.where('jsonb_exists_any(tags, ARRAY[?]::text[])', any) if any.any?
      s = s.where('jsonb_exists_all(tags, ARRAY[?]::text[])', all) if all.any?
      s = s.where('NOT jsonb_exists_any(tags, ARRAY[?]::text[])', none) if none.any?
      s
    end

    def created_condition(s, f)
      s = s.where('whatsapp_contacts.created_at >= ?', Time.zone.parse(f['created_from'].to_s)) if f['created_from'].present?
      s = s.where('whatsapp_contacts.created_at <= ?', Time.zone.parse(f['created_to'].to_s).end_of_day) if f['created_to'].present?
      s
    rescue ArgumentError
      s
    end

    def numeric_conditions(s, f)
      s = s.where('order_count >= ?', f['min_orders'].to_i) if f['min_orders'].present?
      s = s.where('order_count <= ?', f['max_orders'].to_i) if f['max_orders'].present?
      s = s.where('total_spent >= ?', f['min_spent'].to_f) if f['min_spent'].present?
      s = s.where('total_spent <= ?', f['max_spent'].to_f) if f['max_spent'].present?
      s
    end

    def recency_conditions(s, f)
      if f['last_order_within_days'].present?
        s = s.where('last_order_at >= ?', f['last_order_within_days'].to_i.days.ago)
      end
      if f['last_order_older_than_days'].present?
        s = s.where('last_order_at IS NOT NULL AND last_order_at <= ?', f['last_order_older_than_days'].to_i.days.ago)
      end
      s
    end

    def cod_conditions(s, f)
      s = s.where('COALESCE(cod_orders_count, 0) > 0 AND COALESCE(prepaid_orders_count, 0) = 0') if truthy?(f['cod_only'])
      s = s.where('COALESCE(cod_orders_count, 0) >= ?', f['min_cod_orders'].to_i) if f['min_cod_orders'].to_i.positive?
      case f['rto'].to_s
      when 'only' then s = s.where('(COALESCE(rto_orders_count, 0) + COALESCE(returned_orders_count, 0)) > 0')
      when 'exclude' then s = s.where('(COALESCE(rto_orders_count, 0) + COALESCE(returned_orders_count, 0)) = 0')
      end
      days = f['unconfirmed_cod_within_days'].to_i
      s = s.where('last_unconfirmed_cod_at >= ?', days.days.ago) if days.positive?
      s
    end

    def clean_tags(raw)
      WhatsappContact.sanitize_tags(raw)
    end

    def truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value) == true
    end
  end
end
