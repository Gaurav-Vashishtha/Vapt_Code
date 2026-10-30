module Whatsapp
  module CampaignRecipes
    module_function

    class UnknownRecipe < StandardError; end

    RECIPES = [
      {
        key: 'winback_60d',
        title: 'Win back lapsed customers',
        description: "Bring back customers who bought before but haven't ordered in 60 days.",
        audience_summary: "Customers who haven't ordered in 60 days",
        audience_source: 'segment',
        segment: { name: 'Lapsed customers (60 days)', filters: { 'last_order_older_than_days' => '60', 'min_orders' => '1' } },
        template_library_key: 'campaign_winback_offer',
        variable_mapping: { '1' => 'contact.first_name' },
        suggested_name: 'Win back lapsed customers'
      },
      {
        key: 'festive_offer',
        title: 'Festive sale',
        description: 'Announce a festive or seasonal sale to everyone subscribed.',
        audience_summary: 'Everyone subscribed',
        audience_source: 'contacts',
        template_library_key: 'campaign_festive_offer',
        variable_mapping: { '1' => 'contact.first_name' },
        suggested_name: 'Festive sale'
      },
      {
        key: 'cod_to_prepaid',
        title: 'Turn COD buyers into online payers',
        description: 'Offer cash-on-delivery buyers a reason to pay online next time.',
        audience_summary: 'COD buyers who never paid online, with no returns or RTO',
        audience_source: 'segment',
        segment: { name: 'COD buyers, no returns or RTO', filters: { 'cod_only' => true, 'rto' => 'exclude' } },
        template_library_key: 'campaign_prepaid_nudge',
        variable_mapping: { '1' => 'contact.first_name' },
        suggested_name: 'Pay online next time'
      },
      {
        key: 'abandoned_cart_blast',
        title: 'Recover abandoned checkouts',
        description: "Remind shoppers who left a checkout in the last week and didn't come back.",
        audience_summary: "Shoppers who left a checkout 1 to 7 days ago and didn't finish",
        audience_source: 'abandoned_cart',
        template_library_key: 'campaign_cart_recovery',
        variable_mapping: { '1' => 'cart.name', '3' => 'cart.recovery_url' },
        suggested_name: 'Recover abandoned checkouts'
      }
    ].freeze

    def find(key)
      RECIPES.find { |r| r[:key] == key.to_s }
    end

    def index(shop, account: nil)
      account ||= shop.default_whatsapp_account
      RECIPES.map do |recipe|
        entry = TemplateLibrary.find(recipe[:template_library_key])
        template, status = template_state(account, entry)
        {
          key: recipe[:key],
          title: recipe[:title],
          description: recipe[:description],
          audience_summary: recipe[:audience_summary],
          audience_source: recipe[:audience_source],
          template_library_key: recipe[:template_library_key],
          approved_template_id: template&.id,
          template_status: status,
          variable_mapping: recipe[:variable_mapping],
          variable_defaults: variable_defaults(shop, recipe),
          template_payload: template_payload(entry)
        }
      end
    end

    def apply!(shop, key, account: nil)
      recipe = find(key) or raise UnknownRecipe, key.to_s
      account ||= shop.default_whatsapp_account
      entry = TemplateLibrary.find(recipe[:template_library_key])
      template, status = template_state(account, entry)
      segment = recipe[:segment] ? find_or_create_segment!(shop, recipe[:segment]) : nil

      campaign = WhatsappCampaign.create!(
        shop_id: shop.id,
        status: 'draft',
        recipe_key: recipe[:key],
        name: "#{recipe[:suggested_name]} #{Time.current.in_time_zone(zone(shop)).strftime('%-d %b')}",
        audience_source: recipe[:audience_source],
        audience_filter: audience_filter(recipe, shop),
        whatsapp_segment_id: segment&.id,
        whatsapp_account_id: account&.id,
        whatsapp_template_id: template&.id,
        variable_mapping: recipe[:variable_mapping],
        variable_defaults: variable_defaults(shop, recipe),
        missing_value_policy: 'default'
      )

      {
        campaign_id: campaign.id,
        template_needed: template ? nil : entry&.dig(:key),
        template_status: status
      }
    end

    # Matched by name prefix so a resubmission with a suffix
    # (campaign_winback_offer_v1_x) still counts.
    def template_state(account, entry)
      return [nil, nil] unless account && entry

      prefix = ActiveRecord::Base.sanitize_sql_like(entry[:name_suggestion].to_s)
      templates = account.whatsapp_templates.where('whatsapp_templates.name LIKE ?', "#{prefix}%")
                         .order(updated_at: :desc).to_a
      approved = templates.find(&:approved?)
      return [approved, 'approved'] if approved

      [nil, templates.first&.status]
    end

    def template_payload(entry)
      return nil unless entry

      entry.slice(:key, :name_suggestion, :language, :category, :event_type_key, :components, :variable_mapping, :url_button)
    end

    def variable_defaults(shop, recipe)
      defaults = { '2' => shop.owner_name.presence || shop.shopify_domain }
      defaults['1'] = 'there' if recipe[:variable_mapping]['1'].present?
      defaults
    end

    def audience_filter(recipe, shop)
      case recipe[:audience_source]
      when 'abandoned_cart'
        today = Time.current.in_time_zone(zone(shop)).to_date
        {
          'date_from' => (today - 7).iso8601,
          'date_to' => (today - 1).iso8601,
          'exclude_recovered' => true,
          'exclude_recent_automation_hours' => 24
        }
      when 'contacts'
        { 'all' => true }
      else
        {}
      end
    end

    def find_or_create_segment!(shop, spec)
      WhatsappSegment.find_by(shop_id: shop.id, name: spec[:name]) ||
        WhatsappSegment.create!(shop_id: shop.id, name: spec[:name],
                                filters: WhatsappSegment.sanitize_filters(spec[:filters])).tap(&:refresh_count!)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      WhatsappSegment.find_by!(shop_id: shop.id, name: spec[:name])
    end

    def zone(shop)
      zone_class = 'Whatsapp::ShopTimezone'.safe_constantize
      zone = zone_class.respond_to?(:for) ? zone_class.for(shop) : nil
      zone.is_a?(ActiveSupport::TimeZone) ? zone : Time.zone
    end
  end
end
