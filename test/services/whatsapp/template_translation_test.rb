# frozen_string_literal: true

require "test_helper"

# Default-number WhatsApp template translations: component merge, submit validation, MSG91 list
# parsing and the send-language resolver's English fallback.
class Whatsapp::TemplateTranslationTest < ActiveSupport::TestCase
  C = Whatsapp::TemplateComponents
  V = Whatsapp::TemplateTranslationValidator
  L = Whatsapp::TemplateLanguage

  SOURCE = [
    { "type" => "HEADER", "format" => "IMAGE", "example" => { "header_handle" => ["https://x/img.jpg"] } },
    { "type" => "BODY", "text" => "Hi {{1}}, your order {{2}} from {{3}} is confirmed. Thank you!" },
    { "type" => "FOOTER", "text" => "COD King" },
    { "type" => "BUTTONS", "buttons" => [{ "type" => "URL", "text" => "Track order", "url" => "https://t.co/{{1}}" }] }
  ].freeze
  URDU = [
    { "id" => "body", "text" => "السلام علیکم {{1}}، {{3}} سے آپ کا آرڈر {{2}} کنفرم ہو گیا ہے۔ شکریہ!" },
    { "id" => "footer", "text" => "COD King" },
    { "id" => "button_0", "text" => "آرڈر ٹریک کریں" }
  ].freeze

  FakeSetting = Struct.new(:branded_whatsapp_number, :whatsapp_language_code, :whatsapp_order_confirmation_template,
                           :whatsapp_fulfilment_template, :whatsapp_abandoned_cart_template,
                           :whatsapp_cod_verification_template, :whatsapp_first_purchase_template,
                           :whatsapp_pre_verify_otp_template, :whatsapp_prepaid_template_name, keyword_init: true)
  FakeShop = Struct.new(:id, :setting, :country_code)

  setup { L.clear_cache! }

  def shop(language, branded: "", country: "PK")
    FakeShop.new(1, FakeSetting.new(branded_whatsapp_number: branded, whatsapp_language_code: language), country)
  end

  def approve(name, language)
    WhatsappTemplateTranslation.create!(template_name: name, language: language, status: "approved",
                                        source_components: SOURCE, components: C.apply(SOURCE, URDU))
  end

  test "translation merge keeps structure, URLs and media header" do
    out = C.apply(SOURCE, URDU)
    assert_equal %w[HEADER BODY FOOTER BUTTONS], out.map { |c| c["type"] }
    assert_equal "https://t.co/{{1}}", out[3]["buttons"][0]["url"]
    assert_equal ["https://x/img.jpg"], out[0].dig("example", "header_handle")
    assert_empty V.errors(SOURCE, out)
  end

  test "validator blocks dropped variables and changed URLs" do
    dropped = C.apply(SOURCE, URDU.map { |s| s["id"] == "body" ? s.merge("text" => "آپ کا آرڈر کنفرم ہے۔") : s })
    assert V.errors(SOURCE, dropped).any? { |e| e.include?("variables") }

    moved = C.apply(SOURCE, URDU)
    moved[3]["buttons"][0]["url"] = "https://other.example/{{1}}"
    assert V.errors(SOURCE, moved).any? { |e| e.include?("URL must not change") }
  end

  test "MSG91 grouped list response is normalised per language" do
    rows = Msg91::WhatsappTemplateClient.normalize(
      "data" => [{ "name" => "order_confirmation", "category" => "utility",
                   "languages" => [{ "language" => "en", "status" => "APPROVED", "rejection_reason" => "NONE", "code" => SOURCE }] }]
    )
    assert_equal [["order_confirmation", "en", "approved", "UTILITY"]], rows.map { |r| r.values_at(:name, :language, :status, :category) }
    assert_nil rows.first[:rejection_reason]
  end

  test "resolver sends the chosen language only once the template is approved in it" do
    approve("order_confirmation", "ur")
    assert_equal "ur", L.for(shop("ur"), "order_confirmation")
    assert_equal "en", L.for(shop("ur"), "order_fulfilment")
    assert_equal "en", L.for(shop("ar"), "order_confirmation")
  end

  test "resolver leaves English, legacy languages and own-number shops alone" do
    assert_equal "en", L.for(shop("en"), "order_confirmation")
    assert_equal "it", L.for(shop("it"), "order_confirmation_it")
    assert_equal "ur", L.for(shop("ur", branded: "923001234567"), "anything")
  end

  test "onboarding suggestion needs the country default and every previewed template approved" do
    WhatsappCountryLanguage.create!(country_code: "PK", language: "ur")
    assert_equal "en", L.suggested_for(shop("en"))

    L.preview_template_names(shop("en")).each { |name| approve(name, "ur") }
    L.clear_cache!
    assert_equal "ur", L.suggested_for(shop("en"))
    assert_equal "en", L.suggested_for(shop("en", country: "EG"))
  end
end
