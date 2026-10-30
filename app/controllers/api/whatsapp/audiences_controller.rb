module Api
  module Whatsapp
    class AudiencesController < AuthenticatedController
      def preview
        source = params[:audience_source].to_s
        filter = (params[:audience_filter] || {}).to_unsafe_h
        import = params[:whatsapp_audience_import_id].present? ? WhatsappAudienceImport.find_by(id: params[:whatsapp_audience_import_id], shop_id: @shop.id) : nil

        segment_id = params[:whatsapp_segment_id].presence
        sample = collect_sample(source, filter, segment_id)

        # Every source now counts over a per-shop indexed table
        # (whatsapp_contacts / abandoned_carts) so the estimate is cheap; it's
        # still capped + statement-timed and can be skipped with with_count=0.
        count, capped, count_error = [nil, false, nil]
        if ActiveModel::Type::Boolean.new.cast(params.fetch(:with_count, true))
          count, capped, count_error = estimate_count(source, filter, import, segment_id)
        end

        render json: {
          estimated_count: count,
          count_error: count_error,
          count_capped: capped,
          count_cap: COUNT_CAP,
          sample_size: SAMPLE_SIZE,
          fields: ::Whatsapp::AudienceBuilder.catalog(source, import, shop_id: @shop.id),
          sample: sample
        }
      end

      def estimate
        source = params[:audience_source].to_s
        filter = audience_filter_param
        segment_id = params[:whatsapp_segment_id].presence
        import = find_import
        count = params[:count].present? ? params[:count].to_i : estimate_count(source, filter, import, segment_id).first.to_i
        account = find_account
        template = find_template(account)
        cost = ::Whatsapp::CostEstimator.estimate(count: count, category: template&.category.to_s.upcase.presence || 'MARKETING')

        render json: {
          cost: cost.merge(amount: cost[:amount].to_f, rate: cost[:rate].to_f),
          has_non_indian_numbers: non_indian_numbers?(source, filter, segment_id),
          limits: limits_for(account, count),
          quiet_hours: quiet_hours_info
        }
      end

      private

      DAILY_LIMIT_WARNING_SHARE = 0.8
      INDIAN_PHONE_SQL = "whatsapp_contacts.phone LIKE '91%' AND length(whatsapp_contacts.phone) = 12".freeze

      def audience_filter_param
        raw = params[:audience_filter]
        raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : (raw || {}).to_h
      end

      def find_import
        return nil if params[:whatsapp_audience_import_id].blank?
        WhatsappAudienceImport.find_by(id: params[:whatsapp_audience_import_id], shop_id: @shop.id)
      end

      def find_account
        if params[:whatsapp_account_id].present?
          @shop.whatsapp_accounts.find_by(id: params[:whatsapp_account_id])
        else
          @shop.default_whatsapp_account
        end
      end

      def find_template(account)
        return nil if account.nil? || params[:whatsapp_template_id].blank?
        account.whatsapp_templates.find_by(id: params[:whatsapp_template_id])
      end

      def non_indian_numbers?(source, filter, segment_id)
        scope =
          case source
          when 'contacts'
            apply_dates(WhatsappContact.where(shop_id: @shop.id).subscribed, filter, 'whatsapp_contacts.created_at')
          when 'segment'
            WhatsappSegment.find_by(id: segment_id, shop_id: @shop.id)&.matching_scope
          when 'shopify_customer'
            ::Whatsapp::AudienceBuilder.shopify_customer_scope(@shop.id)
          end
        if scope
          return with_statement_timeout { scope.where.not(INDIAN_PHONE_SQL).exists? }
        end
        return false unless source == 'abandoned_cart'

        carts = apply_dates(AbandonedCart.where(shop_id: @shop.id), filter, :created_at)
        with_statement_timeout { carts.where.not(country_code: [nil, '', 'IN']).exists? }
      rescue => e
        Rails.logger.warn("[AudiencesController] non-Indian check failed: #{e.class}: #{e.message}")
        false
      end

      def limits_for(account, count)
        return nil unless account

        daily = account.respond_to?(:messaging_limit) ? account.messaging_limit : nil
        {
          quality_rating: account.quality_rating,
          quality_low: account.respond_to?(:quality_low?) ? account.quality_low? : false,
          quality_warning: account.respond_to?(:quality_warning?) ? account.quality_warning? : false,
          messaging_limit_tier: account.respond_to?(:messaging_limit_tier) ? account.messaging_limit_tier : nil,
          daily_limit: daily,
          exceeds_daily_limit: daily ? count > daily : false,
          near_daily_limit: daily ? count >= (daily * DAILY_LIMIT_WARNING_SHARE) : false
        }
      end

      def quiet_hours_info
        policy_class = '::Whatsapp::SendPolicy'.safe_constantize
        return nil unless policy_class.respond_to?(:in_quiet_hours?) && policy_class.respond_to?(:next_window_start)

        policy = policy_class.respond_to?(:sanitize) ? policy_class.sanitize(params[:send_policy]) : nil
        now = Time.current
        send_at = parse_send_at
        check_at = send_at || now
        in_quiet = policy_class.in_quiet_hours?(@shop, check_at, policy: policy)
        window = in_quiet ? policy_class.next_window_start(@shop, check_at, policy: policy) : nil
        label = policy_class.respond_to?(:quiet_hours_label) ? policy_class.quiet_hours_label(@shop, policy: policy) : nil

        {
          enabled: policy ? policy.dig('quiet_hours', 'enabled') == true : nil,
          in_quiet_hours_now: policy_class.in_quiet_hours?(@shop, now, policy: policy),
          in_quiet_hours_at_send: in_quiet,
          next_window_at: window,
          next_window_display: window ? format_in_shop_tz(window, now) : nil,
          start_display: label&.dig(:start),
          end_display: label&.dig(:end)
        }
      rescue => e
        Rails.logger.warn("[AudiencesController] quiet hours check failed: #{e.class}: #{e.message}")
        nil
      end

      def parse_send_at
        raw = params[:scheduled_at].to_s.strip
        return nil if raw.blank?
        shop_zone.parse(raw)
      rescue ArgumentError
        nil
      end

      def shop_zone
        zone_class = '::Whatsapp::ShopTimezone'.safe_constantize
        zone = zone_class.respond_to?(:for) ? zone_class.for(@shop) : nil
        zone.is_a?(ActiveSupport::TimeZone) ? zone : ActiveSupport::TimeZone['UTC']
      end

      def format_in_shop_tz(time, now)
        local = time.in_time_zone(shop_zone)
        today = now.in_time_zone(shop_zone).to_date
        local.to_date == today ? local.strftime('%-l:%M %p') : local.strftime('%-d %b, %-l:%M %p')
      end

      # Preview is a wizard step, not the launch: bound both the count and the
      # sample so it stays fast on stores with hundreds of thousands of
      # customers / carts. A count over a LIMITed subquery stops scanning once
      # it has seen COUNT_CAP matching rows instead of walking the whole table.
      COUNT_CAP = 50_000
      SAMPLE_SIZE = 5

      # Per-request guard so a pathological count/sample fails cleanly instead
      # of tying up a web dyno until the router times the request out.
      STATEMENT_TIMEOUT_MS = 8_000

      def with_statement_timeout
        ActiveRecord::Base.transaction do
          ActiveRecord::Base.connection.execute("SET LOCAL statement_timeout = #{STATEMENT_TIMEOUT_MS}")
          yield
        end
      end

      def capped_count(scope)
        n = with_statement_timeout { scope.limit(COUNT_CAP).count }
        [n, n >= COUNT_CAP]
      end

      def estimate_count(source, filter, import, segment_id = nil)
        case source
        when 'contacts'
          scope = WhatsappContact.where(shop_id: @shop.id).subscribed
          capped_count(apply_dates(scope, filter, 'whatsapp_contacts.created_at'))
        when 'segment'
          segment = WhatsappSegment.find_by(id: segment_id, shop_id: @shop.id)
          segment ? capped_count(segment.matching_scope) : [0, false]
        else
          legacy_estimate(source, filter, import)
        end
      rescue => e
        Rails.logger.warn("[AudiencesController] count failed: #{e.class}: #{e.message}")
        [0, false, "#{e.class}: #{e.message}".truncate(300)]
      end

      def legacy_estimate(source, filter, import)
        case source
        when 'abandoned_cart'
          scope = AbandonedCart.where(shop_id: @shop.id)
          scope = apply_dates(scope, filter, :created_at)
          scope = scope.where.not('notes ILIKE ?', '%recovered%') if filter['exclude_recovered']
          recent = ::Whatsapp::AudienceBuilder.recent_automation_touches(@shop.id, filter['exclude_recent_automation_hours'])
          capped_count(recent ? exclude_recent_touches(scope, recent) : scope)
        when 'shopify_customer'
          # From the contact book — see AudienceBuilder#shopify_customer.
          scope = ::Whatsapp::AudienceBuilder.shopify_customer_scope(@shop.id)
          capped_count(apply_dates(scope, filter, 'whatsapp_contacts.created_at'))
        when 'csv'
          [import&.valid_count.to_i, false]
        else
          [0, false]
        end
      rescue => e
        Rails.logger.warn("[AudiencesController] count failed: #{e.class}: #{e.message}")
        [0, false, "#{e.class}: #{e.message}".truncate(300)]
      end

      # Bounded so the count query stays small; past it the count is an
      # approximation and the real build applies the full exclusion.
      MAX_EXCLUSION_TERMS = 5_000

      def exclude_recent_touches(scope, recent)
        refs = recent[:refs].to_a.first(MAX_EXCLUSION_TERMS)
        phones = recent[:phones].to_a.first(MAX_EXCLUSION_TERMS)
        if refs.any?
          scope = scope.where('abandoned_carts.checkout_id IS NULL OR abandoned_carts.checkout_id <> ALL(ARRAY[?]::text[])', refs)
        end
        if phones.any?
          scope = scope.where("right(regexp_replace(COALESCE(abandoned_carts.phone, ''), '\\D', '', 'g'), 10) <> ALL(ARRAY[?]::text[])", phones)
        end
        scope
      end

      def collect_sample(source, filter, segment_id = nil)
        out = []
        campaign = WhatsappCampaign.new(shop_id: @shop.id, audience_source: source, audience_filter: filter,
                                        whatsapp_segment_id: segment_id)
        with_statement_timeout do
          ::Whatsapp::AudienceBuilder.each_recipient(campaign, limit: SAMPLE_SIZE) do |r|
            out << { phone: r[:phone], name: r[:name], fields: r[:fields] }
            break if out.size >= SAMPLE_SIZE
          end
        end
        out
      rescue => e
        Rails.logger.warn("[AudiencesController] sample failed: #{e.class}: #{e.message}")
        out
      end

      def apply_dates(scope, filter, col)
        return scope if filter['all']
        scope = scope.where("#{col} >= ?", Time.parse(filter['date_from'])) if filter['date_from'].present?
        scope = scope.where("#{col} <= ?", Time.parse(filter['date_to']).end_of_day) if filter['date_to'].present?
        scope
      end
    end
  end
end
