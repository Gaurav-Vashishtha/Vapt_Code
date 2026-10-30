json.extract! twilio_log, :id, :sid, :ver_type, :country_code, :is_charged, :status, :order_confirmation_id, :shop_id, :created_at, :updated_at
json.url twilio_log_url(twilio_log, format: :json)
