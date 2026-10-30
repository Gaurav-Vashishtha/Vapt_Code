# frozen_string_literal: true

require_relative "engine_test_helper"

class CodFormEngineThankYouTest < Minitest::Test
  include EngineTestHelper
  T = CodForm::Engine::ThankYou

  ORDER = { "id" => "6123456789", "name" => "#1042", "number" => 1042, "total_cents" => 648_640, "status_url" => "https://brand.hu/orders/abc" }.freeze
  CONTACT = { "first_name" => "Anna", "last_name" => "Kiss", "phone_e164" => "+36301234567", "email" => "anna@example.com" }.freeze

  def resolve(thank_you, order: ORDER, locale: "hu")
    T.resolve(config: E::Defaults.form_config.merge("thank_you" => E::Defaults.form_config["thank_you"].merge(thank_you)),
              locale: locale, order: order, contact: CONTACT)
  end

  def test_order_status_page_by_default
    assert_equal({ "type" => "order_status", "url" => "https://brand.hu/orders/abc", "message" => nil, "whatsapp_url" => nil }, resolve({}))
  end

  def test_falls_back_to_the_message_without_a_status_url
    result = resolve({}, order: ORDER.merge("status_url" => nil))
    # The default English message is shown in the buyer's language (default_texts.json).
    assert_equal ["message", nil, "Köszönjük, Anna! A(z) #1042 számú rendelését visszaigazoltuk."], result.values_at("type", "url", "message")
    english = resolve({}, order: ORDER.merge("status_url" => nil), locale: "en")
    assert_equal "Thank you Anna! Your order #1042 is confirmed.", english["message"]
  end

  def test_message_with_variables_and_locale
    result = resolve({ "type" => "message", "message" => { "en" => "Thanks {first_name}", "hu" => "Köszönjük {first_name} {last_name}! {order_name} / {order_number} / {order_id} / {total} / {phone} / {email}" } })
    assert_equal "Köszönjük Anna Kiss! #1042 / 1042 / 6123456789 / 6486.40 / +36301234567 / anna@example.com", result["message"]
    assert_equal "Thanks Anna", resolve({ "type" => "message", "message" => { "en" => "Thanks {first_name}" } }, locale: "fr-CA")["message"]
  end

  def test_custom_url_encodes_values
    result = resolve({ "type" => "custom_url", "url" => "https://brand.hu/thanks?order={order_name}&name={first_name}&mail={email}" })
    assert_equal ["custom_url", "https://brand.hu/thanks?order=%231042&name=Anna&mail=anna%40example.com"], result.values_at("type", "url")
    assert_equal "order_status", resolve({ "type" => "custom_url", "url" => "" })["type"]
  end

  def test_whatsapp
    result = resolve({ "type" => "whatsapp", "whatsapp" => { "phone" => "+36 30 999 0000", "message" => { "en" => "Hi, I just placed order {order_name}." } } })
    assert_equal ["whatsapp", "https://wa.me/36309990000?text=Szia%2C%20most%20adtam%20le%20a%28z%29%20%231042%20rendel%C3%A9st."], result.values_at("type", "whatsapp_url")
    english = resolve({ "type" => "whatsapp", "whatsapp" => { "phone" => "+36 30 999 0000", "message" => { "en" => "Hi, I just placed order {order_name}." } } }, locale: "en")
    assert_equal "https://wa.me/36309990000?text=Hi%2C%20I%20just%20placed%20order%20%231042.", english["whatsapp_url"]
    own = resolve({ "type" => "whatsapp", "whatsapp" => { "phone" => "+36 30 999 0000", "message" => { "en" => "Order {order_name}" } } })
    assert_equal "https://wa.me/36309990000?text=Order%20%231042", own["whatsapp_url"]
    assert_equal "order_status", resolve({ "type" => "whatsapp", "whatsapp" => { "phone" => "", "message" => {} } })["type"]
  end

  def test_accepts_the_bare_thank_you_hash
    assert_equal "message", T.resolve(config: { "type" => "message", "message" => { "en" => "x" } }, locale: "en", order: ORDER, contact: CONTACT)["type"]
  end
end

class CodFormEngineRecoveryTest < Minitest::Test
  R = CodForm::Engine::Recovery

  def test_url
    assert_equal "https://brand.hu/?codk_recover=tok_123-AB", R.url(primary_domain: "brand.hu", token: "tok_123-AB")
    assert_equal "https://brand.hu/?codk_recover=a%20b", R.url(primary_domain: "http://brand.hu", token: "a b")
    assert_equal "https://brand.hu/products/widget?variant=1&codk_recover=t", R.url(primary_domain: "https://brand.hu/products/widget?variant=1", token: "t")
    assert_equal "https://brand.hu/products/widget?codk_recover=t#top", R.url(primary_domain: "https://brand.hu/products/widget#top", token: "t")
  end

  def test_prefill
    session = {
      "contact" => { "phone_e164" => "+36301234567", "phone_national" => "301234567", "email" => "anna@example.com", "first_name" => "Anna" },
      "address" => { "country" => "HU", "city" => "Budapest", "zip" => "1051", "secret" => "x" },
      "cart_snapshot" => { "items" => [{ "variant_id" => 44_111, "quantity" => 2, "properties" => { "Engraving" => "Anna" } }, { "quantity" => 1 }] }
    }
    result = R.prefill(session: session, recovery_discount: { "type" => "percentage", "value" => 10 })
    assert_equal({ "phone" => "301234567", "email" => "anna@example.com", "first_name" => "Anna", "last_name" => "" }, result["contact"])
    assert_equal %w[country province city zip address1 address2], result["address"].keys
    assert_equal [{ "variant_id" => "44111", "quantity" => 2, "properties" => { "Engraving" => "Anna" } }], result["items"]
    assert_equal({ "type" => "percentage", "value" => 10 }, result["discount"])
    assert_nil R.prefill(session: session, recovery_discount: { "type" => nil, "value" => 0 })["discount"]
    assert_equal [], R.prefill(session: {})["items"]
  end
end
