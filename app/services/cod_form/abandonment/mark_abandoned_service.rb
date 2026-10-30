# frozen_string_literal: true

module CodForm
  module Abandonment
    # CodForm::Abandonment::MarkAbandonedService.call(session)   (ARCHITECTURE.md I.4, ABN-1..4)
    #
    # 1. compare-and-set the session to `abandoned` (never races an order being placed)
    # 2. recovery link
    # 3. anchor AbandonedCart (source "cod_form"), like Webhooks::ProcessInboundEventJob#upsert_anchor
    # 4. non-BSP shops: legacy stage rows + ShopifyJobs::AbandonedCartJob (same rules as
    #    schedule_legacy_stages); BSP shops are picked up by
    #    Whatsapp::ScheduleAbandonedCartRemindersJob through AbandonedCart::WEBHOOK_SOURCES
    # 5. optional Shopify draft order (general.abandonment.create_draft_order)
    # 6. Klaviyo / Omnisend "COD Form Abandoned" (gate klaviyo_omnisend)
    #
    # Steps 3–6 are independent: one failing never undoes the others. Returns the recovery URL,
    # or nil when the session was not abandoned by this call. No PII is logged.
    class MarkAbandonedService
      ABANDONABLE = [CodForm::Session::STATUS_OPEN, CodForm::Session::STATUS_OTP_PENDING,
                     CodForm::Session::STATUS_BLOCKED].freeze
      ANCHOR_PREFIX = "codf_"

      def self.call(session)
        new(session).call
      end

      def self.anchor_checkout_id(public_id)
        "#{ANCHOR_PREFIX}#{public_id}"
      end

      def initialize(session)
        @session = session
        @shop = session.shop
      end

      def call
        return nil if @shop.nil? || @session.is_test

        now = Time.current
        token = SecureRandom.urlsafe_base64(18)[0, CodForm::Session::RECOVERY_TOKEN_LENGTH]
        claimed = CodForm::Session.where(id: @session.id, order_id: nil, status: ABANDONABLE)
                                  .update_all(status: CodForm::Session::STATUS_ABANDONED, abandoned_at: now,
                                              recovery_token: token, updated_at: now)
        return nil unless claimed == 1

        @session.reload
        @general = general_config
        url = recovery_url(token)
        if url.nil?
          Rails.logger.warn("[codf/abandon] shop=#{@shop.id} session=#{@session.id} no recovery url (no shop domain)")
          return nil
        end

        anchor = step("anchor") { upsert_anchor(url, now) }
        step("stages") { schedule_legacy_stages(anchor, url, now) } if anchor && !@shop.bsp_abandoned_cart?
        step("draft_order") { create_draft_order(url) } if abandonment["create_draft_order"] == true
        step("crm") { send_crm_events(url, now) }
        url
      end

      private

      def step(name)
        yield
      rescue StandardError => e
        Rails.logger.warn("[codf/abandon] shop=#{@shop.id} session=#{@session.id} step=#{name} failed: #{e.class}")
        nil
      end

      def general_config
        general = CodForm::ShopConfig.for(@shop).general
        general.is_a?(Hash) ? general : {}
      end

      def abandonment
        @general["abandonment"].is_a?(Hash) ? @general["abandonment"] : {}
      end

      def recovery_url(token)
        config = CodForm::ShopConfig.for(@shop)
        RecoveryLink.build(
          primary_domain: @shop.primary_domain.presence || @shop.shopify_domain,
          token: token,
          source: @session.source,
          page_url: hash(@session.tracking)["page_url"],
          allowed_hosts: [@shop.shopify_domain] + Array(config.allowed_origins)
        )
      end

      def contact
        hash(@session.contact)
      end

      def quote
        hash(@session.quote_snapshot)
      end

      def phone
        contact["phone_e164"].to_s.strip
      end

      def first_name
        contact["first_name"].to_s.strip.presence || "Customer"
      end

      def country_code
        (hash(@session.address)["country"].presence || @session.country_code).to_s.upcase
      end

      def total_price
        (quote["total_cents"].to_i / 100.0).round(2)
      end

      def lines
        Array(quote["lines"]).select { |line| line.is_a?(Hash) }
      end

      def featured_image
        lines.map { |line| line["image"].to_s }.find(&:present?).to_s
      end

      # Messages need a phone; an email-only session is still abandoned (and goes to the CRM).
      def upsert_anchor(url, now)
        return nil if phone.blank?

        anchor = @shop.abandoned_carts.find_or_initialize_by(
          checkout_id: self.class.anchor_checkout_id(@session.public_id), is_anchor: true
        )
        anchor.assign_attributes(
          source: "cod_form",
          url: url,
          phone: phone,
          country_code: country_code,
          notif_type: "WHATSAPP",
          total_price: total_price,
          name: first_name,
          featured_image: featured_image,
          shopify_created_at: now.to_s,
          source_payload: source_payload(url, now)
        )
        anchor.save!
        @session.update_columns(abandoned_cart_id: anchor.id)
        anchor
      end

      # {session, items, totals} as the document asks, plus the "checkout" envelope the BSP
      # scheduler and Whatsapp::DispatchEventJob read from every webhook-sourced anchor.
      def source_payload(url, now)
        checkout_id = self.class.anchor_checkout_id(@session.public_id)
        items = lines.map do |line|
          {
            "title" => line["title"].to_s,
            "quantity" => [line["quantity"].to_i, 1].max,
            "price" => format("%.2f", line["unit_price_cents"].to_i / 100.0),
            "variant_id" => line["variant_id"].to_s,
            "product_id" => line["product_id"].to_s,
            "image" => line["image"].to_s
          }
        end
        address = { "phone" => phone, "country_code" => country_code }
        {
          "session" => @session.public_id,
          "items" => items,
          "totals" => { "total_cents" => quote["total_cents"].to_i, "currency" => (@session.currency || quote["currency"]).to_s },
          "checkout" => {
            "id" => checkout_id,
            "token" => checkout_id,
            "abandoned_checkout_url" => url,
            "created_at" => now.to_s,
            "total_price" => format("%.2f", total_price),
            "currency" => (@session.currency || quote["currency"]).to_s,
            "line_items" => items,
            "line_items_count" => items.sum { |item| item["quantity"] }.to_s,
            "phone" => phone,
            "source" => "cod_form",
            "customer" => {
              "first_name" => contact["first_name"].to_s, "last_name" => contact["last_name"].to_s,
              "phone" => phone, "email" => contact["email"].to_s
            },
            "shipping_address" => address,
            "billing_address" => address
          }
        }
      end

      # Same rules as Webhooks::ProcessInboundEventJob#schedule_legacy_stages: one row per
      # configured offset, each with its own ShopifyJobs::AbandonedCartJob. Rows keep a nil
      # status (AbandonedCartJob treats IN_PROGRESS as already sent).
      def schedule_legacy_stages(anchor, url, anchored_at)
        setting = @shop.setting
        return if setting.blank?

        sms_offsets = parse_offsets(setting.ac_sms_schedule) if setting.abandoned_cart_enabled
        whatsapp_offsets = parse_offsets(setting.ac_whatsapp_schedule) if setting.ac_whatsapp
        schedule_stage_rows(anchor, url, "SMS", sms_offsets, anchored_at, setting)
        schedule_stage_rows(anchor, url, "WHATSAPP", whatsapp_offsets, anchored_at, setting)
      end

      def schedule_stage_rows(anchor, url, notif_type, offsets, anchored_at, setting)
        Array(offsets).each_with_index do |offset, index|
          intended_time = anchored_at + offset.minutes
          next if intended_time < 30.minutes.ago

          exists = @shop.abandoned_carts.where(
            checkout_id: anchor.checkout_id, notif_type: notif_type, scheduled_at: intended_time
          ).exists?
          next if exists

          row = @shop.abandoned_carts.new(
            checkout_id: anchor.checkout_id,
            source: anchor.source,
            is_anchor: false,
            url: url,
            shopify_created_at: anchored_at.to_s,
            phone: anchor.phone,
            country_code: anchor.country_code,
            notif_type: notif_type,
            total_price: anchor.total_price,
            name: anchor.name,
            scheduled_at: intended_time,
            featured_image: anchor.featured_image,
            source_payload: anchor.source_payload,
            dynamic_config: (notif_type == "WHATSAPP" ? setting.abandoned_cart_configs&.[](index) : nil)
          )
          next unless row.save

          delay = [(intended_time - Time.current).to_i, 0].max
          begin
            ShopifyJobs::AbandonedCartJob.perform_in(delay.seconds, @shop.id, row.id)
          rescue StandardError => e
            row.destroy
            Rails.logger.error("[codf/abandon] shop=#{@shop.id} failed to schedule #{notif_type}: #{e.class}")
          end
        end
      end

      def parse_offsets(raw)
        raw.to_s.split(",").map(&:strip).reject(&:blank?).map(&:to_i).select { |n| n >= 0 }
      end

      def create_draft_order(url)
        return unless CodForm::Integrations::Registry.gate?(@shop, "abandonment_recovery")

        DraftOrderService.call(@shop, @session, recovery_url: url)
      end

      def send_crm_events(url, now)
        session_hash = @session.attributes.slice("contact", "address", "quote_snapshot", "currency", "country_code")
        profile = CodForm::Integrations::EventPayloads.profile_from_session(session_hash)
        properties = CodForm::Integrations::EventPayloads.abandoned_properties(session_hash, recovery_url: url)
        event = CodForm::Integrations::EventPayloads::EVENT_ABANDONED
        unique = self.class.anchor_checkout_id(@session.public_id)

        CodForm::Integrations::KlaviyoClient.track(
          @shop, event: event, profile: profile, properties: properties, time: now,
                 value_cents: quote["total_cents"], currency: (@session.currency || quote["currency"]).to_s, unique_id: unique
        )
        CodForm::Integrations::OmnisendClient.track(
          @shop, event: event, profile: profile, properties: properties, time: now, event_id: unique
        )
      end

      def hash(value)
        value.is_a?(Hash) ? value : {}
      end
    end
  end
end
