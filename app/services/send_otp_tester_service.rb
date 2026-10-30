# frozen_string_literal: true

require "net/http"
require "securerandom"

# Sends multiple requests to the WhatsApp OTP send endpoint with random phone and cart_token.
# For testing only.
class SendOtpTesterService < ApplicationService
  URL = "https://www.hillteck.com/verify_order_by_whatsapp/Verification_otp/send_otp"
  DEFAULT_HEADERS = {
    "accept" => "*/*",
    "accept-language" => "en-US,en;q=0.9,nl;q=0.8",
    "origin" => "https://www.nariyal.co.in",
    "priority" => "u=1, i",
    "referer" => "https://www.nariyal.co.in/",
    "sec-ch-ua" => '"Not(A:Brand";v="8", "Chromium";v="144", "Google Chrome";v="144"',
    "sec-ch-ua-mobile" => "?0",
    "sec-ch-ua-platform" => '"macOS"',
    "sec-fetch-dest" => "empty",
    "sec-fetch-mode" => "cors",
    "sec-fetch-site" => "cross-site",
    "user-agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36"
  }.freeze

  def initialize(count: 10, shop: "nariyal-cosmetics.myshopify.com", country_code: "in", cookie: nil)
    @count = count
    @shop = shop
    @country_code = country_code
    @cookie = cookie
  end

  def call
    results = []
    @count.times do |i|
      phone = random_phone
      cart_token = random_cart_token
      result = send_request(phone: phone, cart_token: cart_token)
      results << { index: i + 1, phone: phone, cart_token: cart_token }.merge(result)
      puts "Request #{i + 1}/#{@count}: phone=#{phone} -> #{result[:status]} #{result[:message]}"
      puts "Response: #{result[:body]}"
    end
    results
  end

  private

  def random_phone
    first_digit = [7, 8, 9].sample
    rest = 9.times.map { rand(10) }.join
    "+91#{first_digit}#{rest}"
  end

  def random_cart_token
    token_part = SecureRandom.alphanumeric(24)
    key_part = SecureRandom.hex(16)
    "#{token_part}?key=#{key_part}"
  end

  def build_multipart_body(phone:, cart_token:)
    boundary = "----RubyFormBoundary#{SecureRandom.hex(16)}"
    parts = [
      ["shop", @shop],
      ["country_code", @country_code],
      ["phone_with_std_code", phone],
      ["cart_token", cart_token]
    ]
    body = parts.flat_map do |name, value|
      [
        "--#{boundary}\r\n",
        "Content-Disposition: form-data; name=\"#{name}\"\r\n\r\n",
        "#{value}\r\n"
      ]
    end.join
    body += "--#{boundary}--\r\n"
    [boundary, body]
  end

  def send_request(phone:, cart_token:)
    boundary, body = build_multipart_body(phone: phone, cart_token: cart_token)
    uri = URI(URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 10

    req = Net::HTTP::Post.new(uri)
    DEFAULT_HEADERS.each { |k, v| req[k] = v }
    req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
    req["Cookie"] = @cookie if @cookie.present?
    req.body = body

    response = http.request(req)
    {
      status: response.code.to_i,
      message: response.message,
      body: response.body.presence&.slice(0, 500)
    }
  rescue StandardError => e
    { status: 0, message: "error", error: e.message, body: nil }
  end
end
