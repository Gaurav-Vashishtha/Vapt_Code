# frozen_string_literal: true

require 'sidekiq/testing'
Sidekiq::Testing.fake!

module WebhookConsoleTest
  module_function

  def shop
    @shop ||= Shop.find_by(shopify_domain: ENV.fetch("TEST_SHOP", nil)) ||
              Shop.order(:id).first ||
              raise('No shop in the database — set TEST_SHOP or create one first.')
  end

  def endpoint
    @endpoint ||= begin
      e = WebhookEndpoint.find_or_initialize_by(shop_id: shop.id, provider: 'shopflo')
      e.enabled = true
      e.signature_scheme = 'shared_secret'
      e.signature_header = 'X-Webhook-Signature'
      e.save!
      e.update_event_setting!('checkout_abandoned',  'enabled' => true, 'amount_scale' => 1.0)
      e.update_event_setting!('added_to_cart_ui',    'enabled' => true, 'amount_scale' => 0.01)
      e.update_event_setting!('product_page_viewed', 'enabled' => true, 'amount_scale' => 1.0)
      e.reload
    end
  end

  def checkout_abandoned_payload(checkout_id: "test_#{SecureRandom.hex(4)}", phone: '+919123456789')
    {
      'event_name' => 'checkout_abandoned',
      'session_id' => SecureRandom.uuid,
      'checkout_id' => checkout_id,
      'token_id' => "https://checkout.shopflo.co/?tokenId=#{checkout_id}",
      'source' => 'shopflo',
      'abandoned_checkout_url' => '',
      'cart_token' => checkout_id,
      'email' => 'buyer@example.com',
      'phone' => phone,
      'created_at' => 20.minutes.ago.iso8601,
      'note_attributes' => [
        { 'name' => 'shopflo_checkout_url', 'value' => "https://checkout.shopflo.co/?tokenId=#{checkout_id}&resume=1" }
      ],
      'shipping_address' => { 'city' => 'Bangalore', 'country_code' => 'IN', 'zip' => '560078' },
      'billing_address' => { 'city' => 'Bangalore', 'country_code' => 'IN' },
      'line_items' => [
        { 'price' => '799.00', 'id' => '43581879451904', 'product_id' => '8135050133760', 'quantity' => 1, 'title' => 'Pencil Pants' },
        { 'price' => '1599.00', 'id' => '43501980123392', 'product_id' => '8101659902208', 'quantity' => 1, 'title' => 'Cotton Shirt' }
      ],
      'customer' => { 'first_name' => 'Asha', 'last_name' => 'Rao', 'phone' => phone, 'email' => nil, 'marketing_consent' => true },
      'currency' => 'INR', 'subtotal_price' => 2398, 'total_price' => 2398,
      'image_url' => '', 'timestamp' => (Time.current.to_f * 1000).to_i
    }
  end

  def order_completed_payload(checkout_id:, phone: '+919123456789')
    {
      'event_name' => 'order_completed',
      'session_id' => SecureRandom.uuid,
      'checkout_id' => '',
      'cart_token' => checkout_id,
      'token_id' => SecureRandom.uuid,
      'phone' => phone,
      'created_at' => Time.current.iso8601,
      'customer' => { 'phone' => phone, 'first_name' => 'Asha' },
      'shipping_address' => { 'city' => 'Mumbai', 'country_code' => 'IN' },
      'currency' => 'INR', 'total_price' => 2628.85,
      'payment_mode' => 'COD', 'order_id' => 12_121_212, 'order_name' => '#1002',
      'timestamp' => (Time.current.to_f * 1000).to_i
    }
  end

  def normalize(payload, event_name: nil)
    event_name ||= Webhooks::Adapters::Shopflo.event_name_from(payload)
    Webhooks::Adapters::Shopflo.call(
      provider: 'shopflo', event_name: event_name,
      payload: payload, shop: shop, endpoint: endpoint
    )
  end

  def deliver(payload)
    event_name = Webhooks::Adapters::Shopflo.event_name_from(payload)
    record = InboundWebhookEvent.create!(
      shop_id: shop.id,
      webhook_endpoint: endpoint,
      provider: 'shopflo',
      event_name: event_name,
      dedup_key: Webhooks::Adapters::Shopflo.dedup_key_for(event_name, payload),
      payload: payload,
      status: :received,
      received_at: Time.current
    )
    Webhooks::ProcessInboundEventJob.new.perform(record.id)
    record.reload
  end

  def queued
    {
      dispatch: Whatsapp::DispatchEventJob.jobs.map { |j| { event: j['args'][0], stage: j['args'][5], at: j['at'] } },
      legacy:   ShopifyJobs::AbandonedCartJob.jobs.map { |j| { cart_id: j['args'][1], at: j['at'] } }
    }
  end

  def clear_queues!
    Sidekiq::Worker.clear_all
  end

  def report(record)
    anchor = shop.abandoned_carts.find_by(checkout_id: record.payload['checkout_id'].then { |id| "flo_#{id}" }, is_anchor: true)
    {
      delivery_status: record.status,
      skip_reason: record.skip_reason,
      error: record.error,
      mapped_to: record.internal_event_type_key,
      anchor_id: anchor&.id,
      anchor_url: anchor&.url,
      anchor_phone: anchor&.phone,
      anchor_total: anchor&.total_price,
      anchor_notes: anchor&.notes,
      stage_rows: anchor ? shop.abandoned_carts.where(checkout_id: anchor.checkout_id, is_anchor: false).count : 0,
      routing: shop.bsp_abandoned_cart? ? 'BSP (Meta Cloud API)' : 'legacy MSG91',
      queued: queued
    }
  end

  def cleanup!
    ids = shop.abandoned_carts.from_webhooks.pluck(:id)
    shop.abandoned_carts.where(id: ids).delete_all
    shop.inbound_webhook_events.delete_all
    clear_queues!
    "removed #{ids.size} carts and every inbound event for #{shop.shopify_domain}"
  end

  def run!
    clear_queues!
    puts "shop:     #{shop.shopify_domain} (id=#{shop.id})"
    puts "routing:  #{shop.bsp_abandoned_cart? ? 'BSP (Meta Cloud API)' : 'legacy MSG91'}"
    puts "poll off: #{shop.webhook_cart_ingestion?}"
    puts "url:      #{endpoint.ingest_url}"
    puts "secret:   #{endpoint.secret}"
    puts

    payload = checkout_abandoned_payload
    n = normalize(payload)
    puts 'adapter'
    puts "  external id:  #{n.source_external_id}"
    puts "  recovery url: #{n.recovery_url}"
    puts "  phone:        #{n.phone} (#{n.country_code})"
    puts "  total:        #{n.total_price}"
    puts "  anchor at:    #{n.occurred_at}"
    puts "  sendable:     #{n.sendable?}"
    puts

    record = deliver(payload)
    puts 'ingest'
    report(record).each { |k, v| puts "  #{k}: #{v.inspect}" }
    puts

    dup = deliver(payload) rescue nil
    puts "redelivery of the same payload: #{dup ? dup.status : 'rejected by the dedup index'}"
    puts

    recovery = deliver(order_completed_payload(checkout_id: payload['checkout_id']))
    anchor = shop.abandoned_carts.find_by(checkout_id: "flo_#{payload['checkout_id']}", is_anchor: true)
    puts 'suppression'
    puts "  order_completed status: #{recovery.status}"
    puts "  anchor notes now:       #{anchor&.reload&.notes.inspect}"
    puts

    puts 'nothing was sent — Sidekiq::Testing.fake! held every job in memory.'
    puts 'run WebhookConsoleTest.cleanup! to remove the rows this created.'
    :done
  end
end
