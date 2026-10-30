# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class CodForm::FormTest < ActiveSupport::TestCase
  setup do
    @shop = shops(:regular_shop)
  end

  test "default_for creates one published default form per shop" do
    form = CodForm::Form.default_for(@shop)

    assert form.is_default
    assert_equal "Default form", form.name
    assert_equal "active", form.status
    assert_equal 1, form.published_version
    assert_equal CodForm::Engine::Defaults.form_config, form.published_config
    assert_equal form.id, CodForm::Form.default_for(@shop).id
  end

  test "only one default form per shop" do
    CodForm::Form.default_for(@shop)
    second = CodForm::Form.new(shop: @shop, name: "Second", is_default: true)

    assert_not second.valid?
    assert second.errors[:is_default].any?
  end

  test "at most five non-archived forms per shop" do
    CodForm::Form.default_for(@shop)
    4.times { |i| CodForm::Form.create!(shop: @shop, name: "Form #{i}", position: i + 1) }

    sixth = CodForm::Form.new(shop: @shop, name: "Sixth")
    assert_not sixth.valid?

    CodForm::Form.where(shop_id: @shop.id, is_default: false).first.update!(status: "archived")
    assert sixth.valid?
  end

  test "the default form cannot be archived" do
    form = CodForm::Form.default_for(@shop)
    form.status = "archived"
    assert_not form.valid?
  end

  test "publish! copies the normalized draft, bumps versions" do
    form = CodForm::Form.default_for(@shop)

    CodForm::MetafieldSyncJob.stub(:perform_async, nil) do
      form.publish!
    end

    assert_equal 2, form.reload.published_version
    assert_equal form.draft_config, form.published_config
    assert_not_nil form.published_at
    assert_equal 1, CodForm::ShopConfig.for(@shop).config_version
  end

  test "publish! raises and keeps the published config when the draft has errors" do
    form = CodForm::Form.default_for(@shop)
    result = { "config" => {}, "errors" => [{ "path" => "blocks", "code" => "missing_submit" }], "warnings" => [] }

    CodForm::Engine::FormConfig.stub(:normalize, result) do
      assert_raises(ActiveRecord::RecordInvalid) { form.publish! }
    end

    assert_equal 1, form.reload.published_version
    assert_equal result["errors"], form.publish_errors
  end
end
