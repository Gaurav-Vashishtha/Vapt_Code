# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class CodForm::ShopConfigTest < ActiveSupport::TestCase
  setup do
    @shop = shops(:regular_shop)
  end

  test "for creates one row per shop with the documented defaults" do
    config = CodForm::ShopConfig.for(@shop)

    assert config.persisted?
    assert_equal "legacy", config.storefront_mode
    assert_equal "default", config.module_access
    assert_equal({}, config.general)
    assert_equal [], config.allowed_origins
    assert_equal 0, config.config_version
    assert_equal config.id, CodForm::ShopConfig.for(@shop).id
    assert_equal config.id, @shop.cod_form_shop_config.id
  end

  test "cod_form_mode? and enabled_at" do
    config = CodForm::ShopConfig.for(@shop)
    assert_not config.cod_form_mode?
    assert_nil config.enabled_at

    config.update!(storefront_mode: "cod_form")
    assert config.cod_form_mode?
    assert_not_nil config.enabled_at
  end

  test "module_enabled? follows module_access, then the global default" do
    config = CodForm::ShopConfig.for(@shop)

    config.module_access = "on"
    assert config.module_enabled?
    config.module_access = "off"
    assert_not config.module_enabled?

    config.module_access = "default"
    CodForm::GlobalSetting.current.update!(module_default_on: true)
    assert config.module_enabled?
    CodForm::GlobalSetting.current.update!(module_default_on: false)
    assert_not config.module_enabled?
  end

  test "bump_version! with sync: false moves the version and leaves the storefront alone" do
    config = CodForm::ShopConfig.for(@shop)
    enqueued = []

    CodForm::MetafieldSyncJob.stub(:perform_async, ->(shop_id) { enqueued << shop_id }) do
      assert_equal 1, config.bump_version!(sync: false)
    end

    assert_empty enqueued
    assert config.reload.metafield_stale?
  end

  test "bump_version! increments config_version and enqueues the metafield sync" do
    config = CodForm::ShopConfig.for(@shop)
    enqueued = []

    CodForm::MetafieldSyncJob.stub(:perform_async, ->(shop_id) { enqueued << shop_id }) do
      assert_equal 1, config.bump_version!
      assert_equal 2, config.bump_version!
    end

    assert_equal 2, config.reload.config_version
    assert_equal [@shop.id, @shop.id], enqueued
    assert config.metafield_stale?
  end

  test "rejects unknown modes and malformed feature_overrides" do
    config = CodForm::ShopConfig.for(@shop)

    config.storefront_mode = "express"
    assert_not config.valid?

    config.storefront_mode = "legacy"
    config.feature_overrides = { "ab_tests" => "yes" }
    assert_not config.valid?

    config.feature_overrides = { "ab_tests" => true }
    assert config.valid?
    assert_equal true, config.feature_override(:ab_tests)
    assert_nil config.feature_override(:upsell)
  end

  test "inspect does not print the preview token" do
    config = CodForm::ShopConfig.for(@shop)
    token = config.rotate_preview_token!

    assert_equal 32, token.length
    assert config.preview_token_matches?(token)
    assert_not_includes config.inspect, token
  end
end
