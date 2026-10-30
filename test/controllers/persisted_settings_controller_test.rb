require 'test_helper'

class PersistedSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @persisted_setting = persisted_settings(:one)
  end

  test "should get index" do
    get persisted_settings_url, as: :json
    assert_response :success
  end

  test "should create persisted_setting" do
    assert_difference('PersistedSetting.count') do
      post persisted_settings_url, params: { persisted_setting: { shop_id: @persisted_setting.shop_id, test_order_count: @persisted_setting.test_order_count } }, as: :json
    end

    assert_response 201
  end

  test "should show persisted_setting" do
    get persisted_setting_url(@persisted_setting), as: :json
    assert_response :success
  end

  test "should update persisted_setting" do
    patch persisted_setting_url(@persisted_setting), params: { persisted_setting: { shop_id: @persisted_setting.shop_id, test_order_count: @persisted_setting.test_order_count } }, as: :json
    assert_response 200
  end

  test "should destroy persisted_setting" do
    assert_difference('PersistedSetting.count', -1) do
      delete persisted_setting_url(@persisted_setting), as: :json
    end

    assert_response 204
  end
end
