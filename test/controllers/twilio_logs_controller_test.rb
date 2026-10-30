require 'test_helper'

class TwilioLogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @twilio_log = twilio_logs(:one)
  end

  test "should get index" do
    get twilio_logs_url, as: :json
    assert_response :success
  end

  test "should create twilio_log" do
    assert_difference('TwilioLog.count') do
      post twilio_logs_url, params: { twilio_log: { country_code: @twilio_log.country_code, is_charged: @twilio_log.is_charged, order_confirmation_id: @twilio_log.order_confirmation_id, shop_id: @twilio_log.shop_id, sid: @twilio_log.sid, status: @twilio_log.status, ver_type: @twilio_log.ver_type } }, as: :json
    end

    assert_response 201
  end

  test "should show twilio_log" do
    get twilio_log_url(@twilio_log), as: :json
    assert_response :success
  end

  test "should update twilio_log" do
    patch twilio_log_url(@twilio_log), params: { twilio_log: { country_code: @twilio_log.country_code, is_charged: @twilio_log.is_charged, order_confirmation_id: @twilio_log.order_confirmation_id, shop_id: @twilio_log.shop_id, sid: @twilio_log.sid, status: @twilio_log.status, ver_type: @twilio_log.ver_type } }, as: :json
    assert_response 200
  end

  test "should destroy twilio_log" do
    assert_difference('TwilioLog.count', -1) do
      delete twilio_log_url(@twilio_log), as: :json
    end

    assert_response 204
  end
end
