require 'csv'
require 'set'

module Whatsapp
  # Yields normalized recipient hashes for a campaign's audience source. Each hash:
  #   { phone:, name:, email:, source_ref:, fields: { 'cart.name' => ..., ... } }
  # Phone normalization reuses the app's canonical RtoOrder.normalize_phone.
  module AudienceBuilder
    module_function

    # `limit:` bounds how many source rows are read. Without it the builder
    # streams the whole audience in 1000-row batches (and parses a whole CSV),
    # which is right for BuildAudienceJob but far too heavy for the wizard's
    # "preview a few recipients" call — that was timing out on big stores.
    def each_recipient(campaign, limit: nil, &block)
      case campaign.audience_source
      when 'abandoned_cart'   then abandoned_cart(campaign, limit: limit, &block)
      when 'shopify_customer' then shopify_customer(campaign, limit: limit, &block)
      when 'csv'              then csv(campaign, limit: limit, &block)
      when 'contacts'         then contacts(campaign, limit: limit, &block)
      when 'segment'          then segment(campaign, limit: limit, &block)
      end
    end

    # Iterate a scope either fully (find_each) or just the first `limit` rows.
    # Over-fetches a little (x4, capped) so rows that normalize to a blank
    # phone don't leave a short sample.
    def each_row(scope, limit)
      if limit
        scope.limit([limit * 4, 200].min).each { |r| yield r }
      else
        scope.find_each(batch_size: 1000) { |r| yield r }
      end
    end

    CONTACT_FIELDS = %w[
      contact.name contact.first_name contact.last_name contact.email
      contact.phone contact.tags contact.order_count contact.total_spent
    ].freeze

    def catalog(source, import = nil, shop_id: nil)
      case source
      when 'abandoned_cart'
        %w[cart.name cart.recovery_url cart.total cart.phone cart.country]
      when 'shopify_customer'
        %w[customer.first_name customer.last_name customer.email customer.tags customer.order_count]
      when 'csv'
        Array(import&.columns).map { |c| "csv.#{c}" }
      when 'contacts', 'segment'
        keys = shop_id ? WhatsappContact.attr_keys(shop_id).map { |k| "contact.attr.#{k}" } : []
        CONTACT_FIELDS + keys
      else
        []
      end
    end

    def abandoned_cart(campaign, limit: nil)
      filter = campaign.audience_filter || {}
      scope = AbandonedCart.where(shop_id: campaign.shop_id)
      scope = apply_date_range(scope, campaign, :created_at)
      scope = scope.where.not('notes ILIKE ?', '%recovered%') if filter['exclude_recovered']
      recent = recent_automation_touches(campaign.shop_id, filter['exclude_recent_automation_hours'])

      each_row(scope, limit) do |cart|
        phone = normalize(cart.phone, cart.country_code)
        next if phone.blank?
        next if recent && recently_touched?(recent, phone, cart.checkout_id)
        yield(
          phone: phone, name: cart.name, email: nil, source_ref: cart.checkout_id,
          fields: {
            'cart.name' => cart.name, 'cart.recovery_url' => cart.url,
            'cart.total' => cart.total_price, 'cart.phone' => phone,
            'cart.country' => cart.country_code
          }
        )
      end
    end

    AUTOMATION_EVENTS = %w[abandoned_cart cart_abandoned].freeze

    # Phones (last 10 digits) and checkout refs that an automated cart reminder
    # reached in the last `hours`, so a blast doesn't double-message them.
    def recent_automation_touches(shop_id, hours)
      hours = hours.to_i
      return nil unless hours.positive?

      phones = Set.new
      refs = Set.new
      WhatsappMessageLog.where(shop_id: shop_id, event_type_key: AUTOMATION_EVENTS, created_at: hours.hours.ago..)
                        .where.not(status: %i[failed dropped])
                        .pluck(:recipient, :source_external_id)
                        .each do |recipient, ref|
        last10 = recipient.to_s.gsub(/\D/, '').last(10)
        phones << last10 if last10.length >= 8
        refs << ref.to_s if ref.present?
      end
      { phones: phones, refs: refs }
    end

    def recently_touched?(recent, phone, checkout_id)
      recent[:phones].include?(phone.to_s.last(10)) || (checkout_id.present? && recent[:refs].include?(checkout_id.to_s))
    end

    # "Shopify customers" is served from the contact book, NOT from
    # customers ⋈ customer_shop_mappings. Those tables span every shop and have
    # no per-shop index; scanning them per campaign/preview timed out and any
    # index on them would be a large write-amplifying change. The contact book
    # is the per-shop copy that "Sync from store" maintains, and it carries
    # order_count/total_spent already.
    def shopify_customer(campaign, limit: nil)
      scope = shopify_customer_scope(campaign.shop_id)
      scope = apply_date_range(scope, campaign, 'whatsapp_contacts.created_at')

      each_row(scope, limit) do |c|
        yield(
          phone: c.phone, name: c.display_name, email: c.email,
          source_ref: c.source_ref.presence || "contact:#{c.id}",
          fields: {
            'customer.first_name' => c.first_name.presence || c.display_name.to_s.split(' ').first,
            'customer.last_name' => c.last_name,
            'customer.email' => c.email,
            'customer.tags' => Array(c.tags).join(', ').presence,
            'customer.order_count' => c.order_count
          }
        )
      end
    end

    # A "Shopify customer" is any subscribed contact that came in as one OR
    # has placed an order (a contact first seen via an abandoned cart keeps
    # source=abandoned_cart even after ordering — source is first-wins).
    def shopify_customer_scope(shop_id)
      WhatsappContact.where(shop_id: shop_id).subscribed
                     .where("source = 'shopify_customer' OR order_count > 0")
    end

    def csv(campaign, limit: nil)
      import = campaign.whatsapp_audience_import
      return unless import

      phone_col = import.phone_column
      name_col = import.name_column
      email_col = import.email_column

      content = import.raw_content.presence || (import.file.attached? ? import.file.download : nil)
      return if content.blank?

      # Stream instead of CSV.parse so a preview doesn't materialise the whole
      # file; a limit stops reading after `limit` usable rows.
      yielded = 0
      CSV.new(content, headers: true).each_with_index do |row, idx|
        break if limit && yielded >= limit
        raw_phone = phone_col ? row[phone_col] : nil
        phone = normalize(raw_phone, nil)
        next if phone.blank?
        yielded += 1
        fields = row.to_h.transform_keys { |k| "csv.#{k}" }
        yield(
          phone: phone,
          name: name_col ? row[name_col] : nil,
          email: email_col ? row[email_col] : nil,
          source_ref: "csv:#{idx + 1}",
          fields: fields
        )
      end
    end

    def contacts(campaign, limit: nil)
      scope = WhatsappContact.where(shop_id: campaign.shop_id).subscribed
      scope = apply_date_range(scope, campaign, 'whatsapp_contacts.created_at')
      each_row(scope, limit) { |c| yield contact_row(c) }
    end

    def segment(campaign, limit: nil)
      seg = campaign.whatsapp_segment
      return unless seg && seg.shop_id == campaign.shop_id
      each_row(SegmentQuery.scope(campaign.shop_id, seg.filters), limit) { |c| yield contact_row(c) }
    end

    def contact_row(c)
      fields = {
        'contact.name' => c.display_name,
        'contact.first_name' => c.first_name.presence || c.display_name.to_s.split(' ').first,
        'contact.last_name' => c.last_name,
        'contact.email' => c.email,
        'contact.phone' => c.phone,
        'contact.tags' => Array(c.tags).join(', ').presence,
        'contact.order_count' => c.order_count,
        'contact.total_spent' => c.total_spent
      }
      Hash(c.attrs).each { |k, v| fields["contact.attr.#{k}"] = v }
      { phone: c.phone, name: c.display_name, email: c.email, source_ref: "contact:#{c.id}", fields: fields }
    end

    def apply_date_range(scope, campaign, column)
      f = campaign.audience_filter || {}
      return scope if f['all']
      scope = scope.where("#{column} >= ?", Time.parse(f['date_from'])) if f['date_from'].present?
      scope = scope.where("#{column} <= ?", Time.parse(f['date_to']).end_of_day) if f['date_to'].present?
      scope
    end

    def normalize(raw, _country)
      return nil if raw.blank?
      digits = RtoOrder.normalize_phone(raw).to_s.gsub(/\D/, '')
      digits.length >= 8 ? digits : nil
    rescue StandardError
      nil
    end
  end
end
