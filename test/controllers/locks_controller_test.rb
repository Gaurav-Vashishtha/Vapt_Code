require 'test_helper'

class LocksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @lock = locks(:one)
  end

  test "should get index" do
    get locks_url, as: :json
    assert_response :success
  end

  test "should create lock" do
    assert_difference('Lock.count') do
      post locks_url, params: { lock: { value: @lock.value } }, as: :json
    end

    assert_response 201
  end

  test "should show lock" do
    get lock_url(@lock), as: :json
    assert_response :success
  end

  test "should update lock" do
    patch lock_url(@lock), params: { lock: { value: @lock.value } }, as: :json
    assert_response 200
  end

  test "should destroy lock" do
    assert_difference('Lock.count', -1) do
      delete lock_url(@lock), as: :json
    end

    assert_response 204
  end
end
