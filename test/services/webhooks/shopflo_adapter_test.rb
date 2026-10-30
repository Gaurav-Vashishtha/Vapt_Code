require 'test_helper'

class Webhooks::Adapters::ShopfloTest < ActiveSupport::TestCase
  A = Webhooks::Adapters::Shopflo

  # Stands in for a WebhookEndpoint so the adapter can be exercised without
  # touching the database.
  class StubEndpoint
    def initialize(scales = {})
      @scales = scales
    end

    def amount_scale_for(event_name)
      (@scales[event_name.to_s] || 1.0).to_f
    end
  end

  class StubShop
    attr_reader :shopify_domain

    def initialize(domain)
      @shopify_domain = domain
    end
  end

  def shop
    @shop ||= StubShop.new('shopflo.myshopify.com')
  end

  def endpoint
    @endpoint ||= StubEndpoint.new('added_to_cart_ui' => 0.01)
  end

  def normalize(event_name, payload)
    A.call(provider: 'shopflo', event_name: event_name, payload: payload, shop: shop, endpoint: endpoint)
  end

  def checkout_abandoned_payload
    {
      'event_name' => 'checkout_abandoned',
      'session_id' => '6463d2bb-0000-419a-b72f-faed8ff3dd83',
      'checkout_id' => 'abc_def_ghi',
      'token_id' => 'https://checkout.shopflo.co/?tokenId=abc_def_ghi',
      'source' => 'shopflo',
      'abandoned_checkout_url' => '',
      'cart_token' => 'abc_def_ghi',
      'email' => 'buyer@example.com',
      'phone' => '+919000000000',
      'created_at' => '2023-06-12T06:39:22.029830Z',
      'updated_at' => '2023-06-12T06:45:07.859108Z',
      'note_attributes' => [
        { 'name' => 'landing_page', 'value' => '/products/all-day-cotton-pencil-pants' },
        { 'name' => 'shopflo_checkout_url', 'value' => 'https://checkout.shopflo.co/?tokenId=REAL_LINK' },
        { 'name' => 'cart_token', 'value' => 'abc_def_ghi' }
      ],
      'shipping_address' => {
        'address1' => 'Koramangala', 'city' => 'Bangalore', 'country' => 'India',
        'country_code' => 'IN', 'province' => 'Karnataka', 'zip' => '560078'
      },
      'billing_address' => { 'city' => 'Bangalore', 'country_code' => 'IN', 'zip' => '560078' },
      'line_items' => [
        { 'price' => '799.00', 'id' => '43581879451904', 'product_id' => '8135050133760', 'quantity' => 1, 'title' => 'Pencil Pants' },
        { 'price' => '1599.00', 'id' => '43501980123392', 'product_id' => '8101659902208', 'quantity' => 1, 'title' => 'Cotton Shirt' }
      ],
      'customer' => {
        'uid' => 'abc', 'email' => nil, 'first_name' => 'Asha', 'last_name' => 'Rao',
        'phone' => '+919123456789', 'marketing_consent' => true
      },
      'currency' => 'INR', 'subtotal_price' => 2398, 'total_price' => 2398,
      'image_url' => '', 'timestamp' => 1_779_700_813_605
    }
  end

  test 'checkout_abandoned normalizes into the shared checkout.* payload shape' do
    n = normalize('checkout_abandoned', checkout_abandoned_payload)

    assert_equal :trigger, n.role
    assert_equal 'abandoned_cart', n.event_type_key
    assert_equal 'flo_abc_def_ghi', n.source_external_id
    assert_equal '+919123456789', n.phone
    assert_equal 'IN', n.country_code
    assert_equal 'buyer@example.com', n.email, 'top-level email should win when customer.email is null'
    assert_equal 2398.0, n.total_price
    assert_equal true, n.marketing_consent
    assert n.sendable?

    assert_equal ['checkout'], n.payload.keys
    assert_equal '2', n.payload['checkout']['line_items_count']
    assert_equal '799.00', n.payload['checkout']['line_items'][0]['price']
    assert_equal '+919123456789', n.payload.dig('checkout', 'customer', 'phone')
    assert_equal 'IN', n.payload.dig('checkout', 'shipping_address', 'country_code')
  end

  test 'recovery url falls back through note_attributes, token_id, then a constructed link' do
    from_notes = normalize('checkout_abandoned', checkout_abandoned_payload)
    assert_equal 'https://checkout.shopflo.co/?tokenId=REAL_LINK', from_notes.recovery_url

    no_notes = checkout_abandoned_payload.merge('note_attributes' => [])
    assert_equal 'https://checkout.shopflo.co/?tokenId=abc_def_ghi',
                 normalize('checkout_abandoned', no_notes).recovery_url

    # token_id is an object on some events, so it must not be treated as a URL.
    no_token = checkout_abandoned_payload.merge('note_attributes' => [], 'token_id' => {})
    assert_equal 'https://checkout.shopflo.co/?tokenId=abc_def_ghi',
                 normalize('checkout_abandoned', no_token).recovery_url

    declared = checkout_abandoned_payload.merge('abandoned_checkout_url' => 'https://declared.example/r/1')
    assert_equal 'https://declared.example/r/1', normalize('checkout_abandoned', declared).recovery_url
  end

  test 'epoch millisecond timestamps do not land in 1970' do
    without_created_at = checkout_abandoned_payload.except('created_at')
    assert_equal 2026, normalize('checkout_abandoned', without_created_at).occurred_at.year

    assert_equal 2023, normalize('checkout_abandoned', checkout_abandoned_payload).occurred_at.year,
                 'created_at should win over the millisecond timestamp'
  end

  test 'added_to_cart_ui scales paise to rupees and builds a cart permalink' do
    payload = {
      'event_name' => 'added_to_cart_ui',
      'session_id' => 'fe2ddc06-0000-4a6a-8b84-2cbf05c68cb1',
      'line_items' => [
        { 'title' => 'Snowboard', 'quantity' => 2, 'variant_id' => '55589142888521',
          'product_id' => '15510899228745', 'price' => 74_995,
          'product_image' => 'https://cdn.shopify.com/main.jpg' }
      ],
      'currency' => 'INR', 'total_price' => 149_990,
      'user_data' => { 'phone' => '+919812345678', 'email' => 'buyer@example.com', 'firstName' => 'Asha' },
      'timestamp' => 1_779_876_657_975
    }

    n = normalize('added_to_cart_ui', payload)

    assert_equal 'cart_abandoned', n.event_type_key
    assert_equal 'flo_cart_fe2ddc06-0000-4a6a-8b84-2cbf05c68cb1', n.source_external_id
    assert_equal 1499.9, n.total_price
    assert_equal '749.95', n.payload['cart']['line_items'][0]['price']
    assert_equal ['cart'], n.payload.keys
    assert_equal 'https://shopflo.myshopify.com/cart/55589142888521:2?storefront=true', n.recovery_url
    assert_equal 'https://cdn.shopify.com/main.jpg', n.featured_image
  end

  test 'product_page_viewed keys one reminder per session and product' do
    payload = {
      'event_name' => 'product_page_viewed',
      'session_id' => 'fe2ddc06-0000-0000-0000-2cbf05c68cb1',
      'phone' => '+919812345678',
      'timestamp' => 1_779_876_457_771,
      'data' => {
        'product_image' => 'https://cdn.shopify.com/main.jpg',
        'product_url' => 'https://shopflo.myshopify.com/products/snowboard',
        'product_name' => 'Snowboard', 'product_price' => '749.95',
        'user_data' => { 'phone' => '+919812345678', 'firstName' => 'Asha' }
      }
    }

    n = normalize('product_page_viewed', payload)
    assert_equal 'browse_abandoned', n.event_type_key
    assert_equal ['browse'], n.payload.keys
    assert_equal payload['data']['product_url'], n.recovery_url
    assert_equal n.source_external_id, normalize('product_page_viewed', payload).source_external_id

    other = payload.deep_dup
    other['data']['product_url'] = 'https://shopflo.myshopify.com/products/other'
    refute_equal n.source_external_id, normalize('product_page_viewed', other).source_external_id
  end

  test 'order_completed suppresses everything and carries ids matching every funnel prefix' do
    payload = {
      'event_name' => 'order_completed',
      'session_id' => 'fe2ddc06-0000-0000-0000-2cbf05c68cb1',
      'checkout_id' => '', 'cart_token' => 'abc_def_ghi',
      'token_id' => '8fc24a27-0000-0000-0000-02473d275b6c',
      'phone' => '+919812345678',
      'created_at' => '2026-05-27T10:01:19.419291Z',
      'customer' => { 'phone' => '+919812345678', 'first_name' => 'Asha' },
      'currency' => 'INR', 'total_price' => 2628.85, 'order_id' => 12_121_212
    }

    n = normalize('order_completed', payload)
    assert_equal :suppress, n.role
    assert n.marks_recovered
    assert_equal %w[abandoned_cart cart_abandoned browse_abandoned], n.suppresses
    assert_includes n.external_references, 'flo_abc_def_ghi'
    assert_includes n.external_references, 'flo_cart_fe2ddc06-0000-0000-0000-2cbf05c68cb1'
  end

  test 'checkout_clicked suppresses only the earlier funnel and never marks recovered' do
    payload = {
      'event_name' => 'checkout_clicked',
      'session_id' => 'fe2ddc06-0000-4a6a-8b84-2cbf05c68cb1',
      'checkout_id' => '604a57b3', 'token_id' => '8fc24a27',
      'user_data' => { 'phone' => '+919812345678' }, 'timestamp' => 1_779_876_709_686
    }

    n = normalize('checkout_clicked', payload)
    assert_equal :suppress, n.role
    refute n.marks_recovered
    assert_equal %w[cart_abandoned browse_abandoned], n.suppresses
  end

  test 'unmapped and unusable payloads are ignored rather than raising' do
    assert_equal :ignore, normalize('collection_page_viewed', { 'event_name' => 'collection_page_viewed' }).role
    assert_equal :ignore, normalize('store_page_view', { 'eventName' => 'store_page_view' }).role
    assert_equal :ignore, normalize('checkout_abandoned', { 'event_name' => 'checkout_abandoned' }).role
  end

  test 'event name detection handles both key spellings Shopflo uses' do
    assert_equal 'checkout_abandoned', A.event_name_from(checkout_abandoned_payload)
    assert_equal 'store_page_view', A.event_name_from('eventName' => 'store_page_view')
    assert_nil A.event_name_from({})
  end

  test 'dedup key is stable per delivery and changes when the cart is updated' do
    key = A.dedup_key_for('checkout_abandoned', checkout_abandoned_payload)
    assert_equal key, A.dedup_key_for('checkout_abandoned', checkout_abandoned_payload)
    assert_includes key, 'abc_def_ghi'

    mutated = checkout_abandoned_payload.merge('timestamp' => 1_779_700_813_999)
    refute_equal key, A.dedup_key_for('checkout_abandoned', mutated)
  end
end

class Webhooks::SourceRegistryTest < ActiveSupport::TestCase
  R = Webhooks::SourceRegistry

  test 'known providers resolve and unknown ones do not' do
    assert R.provider?('shopflo')
    refute R.provider?('definitely-not-a-provider')
    assert_equal Webhooks::Adapters::Shopflo, R.adapter_for('shopflo')
  end

  test 'provider events map onto Whatsapp::EventRegistry keys' do
    assert_equal 'abandoned_cart', R.event_type_key_for('shopflo', 'checkout_abandoned')
    assert_equal 'cart_abandoned', R.event_type_key_for('shopflo', 'added_to_cart_ui')
    assert_equal 'browse_abandoned', R.event_type_key_for('shopflo', 'product_page_viewed')

    R.events_for('shopflo').each do |name, definition|
      next unless definition[:role] == :trigger

      assert Whatsapp::EventRegistry.find(definition[:event_type_key]),
             "#{name} maps to #{definition[:event_type_key]}, which is not in Whatsapp::EventRegistry"
    end
  end

  test 'triggers ship disabled and suppressors ship enabled' do
    R.events_for('shopflo').each do |name, definition|
      case definition[:role]
      when :trigger
        refute definition[:default_enabled], "#{name} must not send until a human turns it on"
      when :suppress
        assert definition[:default_enabled], "#{name} can only prevent messages, so it should default on"
      end
    end
  end
end
