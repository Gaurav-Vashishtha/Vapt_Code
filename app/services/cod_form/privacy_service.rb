# frozen_string_literal: true

module CodForm
  # Shopify privacy webhooks for the COD Form data (NFR-8, ARCHITECTURE.md I.6).
  #
  #   PrivacyService.redact_customer(shop, phone:, email:)  -> counts
  #   PrivacyService.export_customer(shop, phone:, email:)  -> stored data (Hash)
  #   PrivacyService.redact_shop(shop)                      -> counts
  #   PrivacyService.handle_webhook(topic:, payload:)       -> dispatches the three topics
  #
  # Covers form sessions, abandoned forms (anchor and stage rows in abandoned_carts with source
  # "cod_form"), block lists, rejections and funnel events. Nothing here logs a phone, an
  # email or any other buyer data: log lines carry ids and counts only.
  class PrivacyService
    TOPIC_DATA_REQUEST = "customers/data_request"
    TOPIC_CUSTOMER_REDACT = "customers/redact"
    TOPIC_SHOP_REDACT = "shop/redact"
    TOPICS = [TOPIC_DATA_REQUEST, TOPIC_CUSTOMER_REDACT, TOPIC_SHOP_REDACT].freeze
    EXPORT_LIMIT = 500

    class << self
      # payload: the webhook body (Hash). Returns a Hash for the topics handled, nil otherwise.
      def handle_webhook(topic:, payload:)
        topic = topic.to_s
        return nil unless TOPICS.include?(topic)

        payload = payload.respond_to?(:to_unsafe_h) ? payload.to_unsafe_h : payload
        payload = payload.is_a?(Hash) ? payload.deep_stringify_keys : {}
        shop = Shop.find_by(shopify_domain: payload["shop_domain"].to_s.strip.downcase)
        return nil if shop.nil?

        customer = payload["customer"].is_a?(Hash) ? payload["customer"] : {}
        case topic
        when TOPIC_SHOP_REDACT then redact_shop(shop)
        when TOPIC_CUSTOMER_REDACT then redact_customer(shop, phone: customer["phone"], email: customer["email"])
        when TOPIC_DATA_REQUEST
          data = export_customer(shop, phone: customer["phone"], email: customer["email"])
          Rails.logger.info("[codf/privacy] data_request shop=#{shop.id} sessions=#{data['sessions'].size}")
          data
        end
      end

      # Blanks contact, address, ip, custom_fields (and the other buyer columns) on matching
      # sessions; deletes matching block entries, rejections, funnel events and abandoned-form
      # rows. Orders themselves live in Shopify and are redacted there.
      def redact_customer(shop, phone: nil, email: nil)
        sessions = matching_sessions(shop, phone, email)
        ids = sessions.pluck(:id)
        public_ids = sessions.pluck(:public_id)
        client_ids = sessions.where.not(client_id: [nil, ""]).pluck(:client_id)
        ips = sessions.where.not(ip: [nil, ""]).distinct.pluck(:ip)
        counts = { "sessions" => ids.size }

        counts["abandoned_carts"] = delete_abandoned_carts(shop, public_ids)
        counts["events"] = delete_events(shop, public_ids + client_ids)
        counts["rejections"] = delete_rejections(shop, public_ids, ips)
        counts["block_entries"] = delete_block_entries(shop, phone, email)

        CodForm::Session.where(id: ids).in_batches(of: 1_000) do |batch|
          # quote_snapshot.order_response is the stored order answer (it holds the buyer email
          # for the web pixel); the rest of the quote is prices and product ids.
          batch.update_all(
            [
              "contact = '{}'::jsonb, address = '{}'::jsonb, custom_fields = '{}'::jsonb, tracking = '{}'::jsonb, " \
              "attribution = '{}'::jsonb, quote_snapshot = quote_snapshot - 'order_response', ip = NULL, " \
              "user_agent = NULL, client_id = NULL, phone_normalized = NULL, email_normalized = NULL, " \
              "recovery_token = NULL, abandoned_cart_id = NULL, updated_at = ?",
              Time.current
            ]
          )
        end

        Rails.logger.info("[codf/privacy] redact_customer shop=#{shop.id} #{counts.map { |k, v| "#{k}=#{v}" }.join(' ')}")
        counts
      end

      # What the module stores about this buyer, for a customers/data_request.
      def export_customer(shop, phone: nil, email: nil)
        sessions = matching_sessions(shop, phone, email).order(created_at: :desc).limit(EXPORT_LIMIT)
        public_ids = sessions.map(&:public_id)
        {
          "shop" => shop.shopify_domain,
          "sessions" => sessions.map do |session|
            {
              "session_id" => session.public_id, "status" => session.status, "created_at" => session.created_at&.utc&.iso8601,
              "contact" => session.contact, "address" => session.address, "custom_fields" => session.custom_fields,
              "ip" => session.ip, "user_agent" => session.user_agent, "country_code" => session.country_code,
              "cart" => session.cart_snapshot, "attribution" => session.attribution,
              "order_id" => session.order_id, "order_name" => session.order_name,
              "ordered_at" => session.ordered_at&.utc&.iso8601, "abandoned_at" => session.abandoned_at&.utc&.iso8601
            }
          end,
          "abandoned_forms" => shop.abandoned_carts.where(source: "cod_form", checkout_id: anchor_ids(public_ids))
                                   .limit(EXPORT_LIMIT)
                                   .map { |cart| cart.attributes.slice("checkout_id", "phone", "name", "country_code", "total_price", "notif_type", "created_at", "notes") },
          "block_entries" => block_entries_for(shop, phone, email).limit(EXPORT_LIMIT)
                                                                 .map { |entry| { "kind" => entry.kind, "value" => entry.value, "created_at" => entry.created_at&.utc&.iso8601 } },
          "rejections" => CodForm::Rejection.where(shop_id: shop.id, session_public_id: public_ids).limit(EXPORT_LIMIT)
                                            .map { |row| row.attributes.slice("reason_code", "stage", "subject_kind", "subject_masked", "created_at") },
          "events_count" => public_ids.empty? ? 0 : FormFunnelEvent.where(shop_id: shop.id, session_token: public_ids).count
        }
      end

      # shop/redact: every cod_* row of the shop, its usage, pixels, integrations, stats and
      # cf_* events. Global tables (plan limits, gates, country groups) are not shop data.
      def redact_shop(shop)
        counts = {}
        counts["abandoned_carts"] = shop.abandoned_carts.where(source: "cod_form").delete_all
        counts["events"] = delete_in_batches(
          FormFunnelEvent.where(shop_id: shop.id, event_type: CodForm::Analytics::EventMeta::EVENT_TYPES)
        )
        {
          "sessions" => CodForm::Session, "rejections" => CodForm::Rejection, "block_entries" => CodForm::BlockEntry,
          "pixels" => CodForm::TrackingPixel, "integrations" => CodForm::Integration, "daily_stats" => CodForm::DailyStat,
          "usages" => CodForm::OrderUsage, "offers" => CodForm::Offer, "ab_tests" => CodForm::AbTest,
          "shipping_rates" => CodForm::ShippingRate, "forms" => CodForm::Form, "button_configs" => CodForm::ButtonConfig,
          "shop_configs" => CodForm::ShopConfig
        }.each do |name, model|
          counts[name] = delete_in_batches(model.where(shop_id: shop.id))
        end
        CodForm::PlanLimit.where(scope_type: "shop", scope_key: shop.id.to_s).delete_all
        purge_redis(shop)

        Rails.logger.info("[codf/privacy] redact_shop shop=#{shop.id} #{counts.map { |k, v| "#{k}=#{v}" }.join(' ')}")
        counts
      end

      private

      def matching_sessions(shop, phone, email)
        digits = CodForm::BlockEntry.normalize("phone", phone)
        mail = email.to_s.strip.downcase
        scope = CodForm::Session.where(shop_id: shop.id)
        conditions = []
        values = {}
        if digits.length >= 5
          conditions << "phone_normalized = :digits"
          conditions << "regexp_replace(coalesce(contact->>'phone_e164', ''), '\\D', '', 'g') = :digits"
          values[:digits] = digits
        end
        if mail.include?("@")
          conditions << "email_normalized = :mail"
          conditions << "lower(coalesce(contact->>'email', '')) = :mail"
          values[:mail] = mail
        end
        return scope.none if conditions.empty?

        scope.where(conditions.join(" OR "), values)
      end

      def anchor_ids(public_ids)
        public_ids.map { |id| CodForm::Abandonment::MarkAbandonedService.anchor_checkout_id(id) }
      end

      def delete_abandoned_carts(shop, public_ids)
        return 0 if public_ids.empty?

        shop.abandoned_carts.where(source: "cod_form", checkout_id: anchor_ids(public_ids)).delete_all
      end

      def delete_events(shop, tokens)
        tokens = tokens.compact.uniq
        return 0 if tokens.empty?

        total = 0
        tokens.each_slice(500) do |slice|
          total += FormFunnelEvent.where(shop_id: shop.id, session_token: slice,
                                         event_type: CodForm::Analytics::EventMeta::EVENT_TYPES).delete_all
        end
        total
      end

      def delete_rejections(shop, public_ids, ips)
        total = 0
        total += CodForm::Rejection.where(shop_id: shop.id, session_public_id: public_ids).delete_all unless public_ids.empty?
        total += CodForm::Rejection.where(shop_id: shop.id, ip: ips).delete_all unless ips.empty?
        total
      end

      def block_entries_for(shop, phone, email)
        digits = CodForm::BlockEntry.normalize("phone", phone)
        mail = CodForm::BlockEntry.normalize("email", email)
        scope = CodForm::BlockEntry.where(shop_id: shop.id)
        phone_scope = digits.length >= 5 ? scope.where(kind: "phone", value_normalized: digits) : scope.none
        mail_scope = mail.include?("@") ? scope.where(kind: "email", value_normalized: mail) : scope.none
        phone_scope.or(mail_scope)
      end

      def delete_block_entries(shop, phone, email)
        block_entries_for(shop, phone, email).delete_all
      end

      def delete_in_batches(scope, batch: 5_000)
        total = 0
        loop do
          ids = scope.limit(batch).pluck(:id)
          break if ids.empty?

          total += scope.klass.where(id: ids).delete_all
        end
        total
      end

      # Button-view counters and notice markers of the shop.
      def purge_redis(shop)
        today = Time.current.utc.to_date
        keys = (-1..3).map { |i| CodForm::FunnelLogger.button_view_key(shop.id, today - i) }
        Sidekiq.redis { |redis| keys.each { |key| redis.del(key) } }
        CodForm::Cache.store.delete(CodForm::OtpUnavailableNotifyJob.cache_key(shop.id))
      rescue StandardError => e
        Rails.logger.warn("[codf/privacy] redis purge failed shop=#{shop.id} #{e.class}")
      end
    end
  end
end
