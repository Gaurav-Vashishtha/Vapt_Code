# frozen_string_literal: true

module CodForm
  module Tracking
    # Sends one clearly synthetic event to a single pixel so the merchant can check the id and
    # token (admin `POST /cod_form/pixels/:id/test`). Uses the vendor's validation mode where
    # one exists (GA4 debug endpoint, Snapchat /validate, Pinterest ?test=true); Meta and TikTok
    # show the event under "Test events" when config.test_event_code is set.
    #
    #   CodForm::Tracking::TestEvent.call(pixel_record) -> {"ok" => bool, "response" => {...}}
    class TestEvent
      def self.call(pixel_record)
        pixel = {
          "id" => pixel_record.id, "platform" => pixel_record.platform, "pixel_id" => pixel_record.pixel_id.to_s,
          "access_token" => pixel_record.access_token.to_s,
          "config" => (pixel_record.config.is_a?(Hash) ? pixel_record.config : {}).merge(
            "events" => { "form_open" => true, "purchase" => true }
          ),
          "targeting" => {}
        }
        outcome =
          case pixel["platform"]
          when "meta" then MetaClient.send_event(pixel: pixel, event: sample_event)
          when "tiktok" then TiktokClient.send_event(pixel: pixel, event: sample_event)
          when "ga4" then Ga4Client.send_event(pixel: pixel, event: sample_event, validate: true)
          when "snapchat" then SnapchatClient.send_event(pixel: pixel, event: sample_event, validate: true)
          when "pinterest" then PinterestClient.send_event(pixel: pixel, event: sample_event, validate: true)
          else Http.skipped("browser_only")
          end

        {
          "ok" => outcome["ok"] && outcome["skipped"].nil?,
          "response" => {
            "status" => outcome["status"], "skipped" => outcome["skipped"], "error" => outcome["error"]
          }.merge(outcome["response"].is_a?(Hash) ? outcome["response"] : {}).reject { |_, v| v.nil? }
        }
      rescue StandardError => e
        { "ok" => false, "response" => { "error" => e.class.name } }
      end

      def self.sample_event
        id = SecureRandom.hex(6)
        {
          "moment" => EventMap::MOMENT_INITIATE_CHECKOUT, "event_time" => Time.current.to_i,
          "session_id" => "test_#{id}", "order_id" => nil, "value_cents" => 100, "currency" => "USD",
          "shipping_cents" => 0, "tax_cents" => 0, "coupon" => nil,
          "contents" => [{ "id" => "codking-test", "product_id" => "codking-test", "title" => "COD King test event",
                           "quantity" => 1, "price_cents" => 100 }],
          "num_items" => 1, "page_url" => nil,
          "user" => { "email" => "test-#{id}@example.com", "external_id" => "test_#{id}" },
          "attribution" => {}, "consent" => { "analytics" => true, "marketing" => true, "sale_of_data" => true }
        }
      end
    end
  end
end
