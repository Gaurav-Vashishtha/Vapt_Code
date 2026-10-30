# frozen_string_literal: true

# Pure parts of the WS6 admin services. Plain minitest, no Rails:
#   ruby test/services/cod_form/admin_services_test.rb
require_relative "support/plain_boot"
require "json"
require "tmpdir"

module ActionController
  class Base; end unless const_defined?(:Base)
end

require_relative "../../../app/services/cod_form/embed_status_service"
require_relative "../../../app/services/cod_form/merchant_audit"
require_relative "../../../app/services/cod_form/domain_sync_service"
require_relative "../../../app/services/cod_form/enable_service"
require_relative "../../../app/controllers/cod_form_admin/preview_frames_controller"

class CodFormEmbedStatusServiceTest < Minitest::Test
  Service = CodForm::EmbedStatusService
  UUID = "0d5a1c1e-1111-2222-3333-444455556666"

  def settings(blocks)
    JSON.generate("current" => { "blocks" => blocks })
  end

  def test_tells_the_two_embeds_apart
    data = settings(
      "1" => { "type" => "shopify://apps/cod-king/blocks/app-embed/#{UUID}", "disabled" => false },
      "2" => { "type" => "shopify://apps/cod-king/blocks/cod-form-embed/#{UUID}", "disabled" => true },
      "3" => { "type" => "shopify://apps/other-app/blocks/app-embed/abc", "disabled" => false }
    )
    assert_equal({ "enabled" => false, "legacy_enabled" => true }, Service.parse(data, extension_uuid: UUID))

    both = settings(
      "1" => { "type" => "shopify://apps/cod-king/blocks/app-embed/#{UUID}", "disabled" => false },
      "2" => { "type" => "shopify://apps/cod-king/blocks/cod-form-embed/#{UUID}", "disabled" => false }
    )
    assert_equal({ "enabled" => true, "legacy_enabled" => true }, Service.parse(both, extension_uuid: UUID))
  end

  def test_new_embed_only
    data = settings("9" => { "type" => "shopify://apps/cod-king-dev/blocks/cod-form-embed/#{UUID}" })
    assert_equal({ "enabled" => true, "legacy_enabled" => false }, Service.parse(data, extension_uuid: UUID))
    assert_equal({ "enabled" => true, "legacy_enabled" => false }, Service.parse(data))
  end

  def test_another_apps_block_with_the_same_handle_does_not_count
    data = settings("9" => { "type" => "shopify://apps/someone-else/blocks/cod-form-embed/ffff", "disabled" => false })
    assert_equal({ "enabled" => false, "legacy_enabled" => false }, Service.parse(data, extension_uuid: UUID))
  end

  def test_preset_name_as_current_and_broken_input
    data = JSON.generate("current" => "Default",
                         "presets" => { "Default" => { "blocks" => { "1" => { "type" => "shopify://apps/cod-king/blocks/cod-form-embed/#{UUID}", "disabled" => false } } } })
    assert_equal true, Service.parse(data, extension_uuid: UUID)["enabled"]
    assert_equal({ "enabled" => false, "legacy_enabled" => false }, Service.parse("{not json"))
    assert_equal({ "enabled" => false, "legacy_enabled" => false }, Service.parse(JSON.generate("current" => {})))
    assert_equal({ "enabled" => false, "legacy_enabled" => false }, Service.parse(JSON.generate([])))
  end

  def test_theme_editor_url
    assert_equal "https://brand.myshopify.com/admin/themes/current/editor?context=apps&template=product&activateAppId=#{UUID}/cod-form-embed",
                 Service.theme_editor_url("brand.myshopify.com", UUID)
    assert_equal "https://brand.myshopify.com/admin/themes/current/editor?context=apps",
                 Service.theme_editor_url("brand.myshopify.com", nil)
  end
end

class CodFormMerchantAuditTest < Minitest::Test
  Audit = CodForm::MerchantAudit

  def test_field_prefix
    assert_equal "cod_form.storefront_mode", Audit.field_name("storefront_mode")
    assert_equal "cod_form.button.preset", Audit.field_name("cod_form.button.preset")
  end

  def test_diff_reports_changed_leaves_only
    old = { "countries" => ["HU"], "pages" => { "product" => true, "cart" => true }, "otp" => { "mode" => "before_order" } }
    new = { "countries" => %w[HU CO], "pages" => { "product" => true, "cart" => false }, "otp" => { "mode" => "before_order" } }
    assert_equal [["general.countries", ["HU"], %w[HU CO]], ["general.pages.cart", true, false]], Audit.diff("general", old, new)
    assert_equal [], Audit.diff("general", old, old)
    assert_equal [["x.added", nil, 1]], Audit.diff("x", {}, { "added" => 1 })
  end

  def test_values_are_truncated_and_secrets_hidden
    assert_equal "", Audit.format_value("cod_form.x", nil)
    assert_equal "true", Audit.format_value("cod_form.x", true)
    assert_equal '["HU","CO"]', Audit.format_value("cod_form.general.countries", %w[HU CO])
    assert_equal 250, Audit.format_value("cod_form.x", "a" * 1_000).length
    assert_equal "[changed]", Audit.format_value("cod_form.general.autocomplete.google_api_key", "AIza-secret")
    assert_equal "", Audit.format_value("cod_form.general.autocomplete.google_api_key", "")
    assert_equal "[changed]", Audit.format_value("cod_form.pixel.7.access_token", "EAAG")
  end
end

class CodFormDomainSyncServiceTest < Minitest::Test
  Service = CodForm::DomainSyncService

  def test_clean
    hosts = ["WWW.Brand.com", "https://brand.hu/", "brand.myshopify.com", "brand.com", "www.brand.com", "bad host", nil, "brand.co:443"]
    assert_equal %w[www.brand.com brand.hu brand.co],
                 Service.clean(hosts, shopify_domain: "brand.myshopify.com", primary_domain: "https://brand.com")
    assert_equal [], Service.clean(nil, shopify_domain: "a.myshopify.com", primary_domain: nil)
    assert_equal 50, Service.clean((1..80).map { |n| "s#{n}.brand.com" }, shopify_domain: "a.myshopify.com", primary_domain: nil).size
  end
end

class CodFormEnableServiceTextsTest < Minitest::Test
  Service = CodForm::EnableService

  def test_missing_file_falls_back_to_built_in_english
    texts = Service.load_texts(File.join(Dir.tmpdir, "codf-missing-#{Process.pid}.json"))
    assert_equal Service::FALLBACK_TEXTS, texts
    assert_equal "Cash on Delivery", texts["en"]["title"]
    assert_equal "Complete order — {total}", texts["en"]["submit"]
  end

  def test_reads_both_shapes_and_tolerates_garbage
    assert_equal({ "en" => { "title" => "T" }, "hu" => { "title" => "U" } },
                 Service.parse_texts(JSON.generate("en" => { "title" => "T" }, "hu" => { "title" => "U" })))
    assert_equal({ "en" => { "title" => "T" } }, Service.parse_texts(JSON.generate("texts" => { "en" => { "title" => "T" } })))
    assert_equal Service::FALLBACK_TEXTS, Service.parse_texts("{broken")
    assert_equal Service::FALLBACK_TEXTS, Service.parse_texts("[]")
    merged = Service.parse_texts(JSON.generate("hu" => { "title" => "U" }))
    assert_equal %w[en hu], merged.keys
  end

  def test_file_is_reloaded_when_it_changes
    Dir.mktmpdir do |dir|
      path = File.join(dir, "default_texts.json")
      File.write(path, JSON.generate("en" => { "title" => "One" }))
      assert_equal "One", Service.load_texts(path)["en"]["title"]
      File.write(path, JSON.generate("en" => { "title" => "Two" }))
      File.utime(Time.now + 5, Time.now + 5, path)
      assert_equal "Two", Service.load_texts(path)["en"]["title"]
    end
  end
end

class CodFormPreviewAssetBaseTest < Minitest::Test
  Controller = CodFormAdmin::PreviewFramesController
  UUID = "0d5a1c1e-1111-2222-3333-444455556666"

  def test_only_this_apps_extension_folder_is_accepted
    base = "https://cdn.shopify.com/extensions/#{UUID}/0.0.0/assets/"
    assert_equal base, Controller.safe_asset_base(base, UUID)
    assert_equal base, Controller.safe_asset_base(base.chomp("/"), UUID)
    assert_nil Controller.safe_asset_base("https://cdn.shopify.com/extensions/other-uuid/assets/", UUID)
    assert_nil Controller.safe_asset_base("https://evil.example/extensions/#{UUID}/assets/", UUID)
    assert_nil Controller.safe_asset_base("#{base}../../x/", UUID)
    assert_nil Controller.safe_asset_base("#{base}\"><script>", UUID)
    # No extension id configured: any extension folder on Shopify's CDN, nothing else.
    assert_equal base, Controller.safe_asset_base(base, nil)
    assert_nil Controller.safe_asset_base("https://evil.example/extensions/x/assets/", nil)
    assert_nil Controller.safe_asset_base("", nil)
    assert_nil Controller.safe_asset_base(nil, UUID)
  end

  def test_csp_matches_the_architecture
    assert_equal "default-src 'none'; script-src https://cdn.shopify.com 'unsafe-inline'; style-src 'unsafe-inline'; " \
                 "img-src https: data:; frame-ancestors https://admin.shopify.com https://*.myshopify.com 'self'", Controller::CSP
  end
end
