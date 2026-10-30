require 'open3'
require 'json'

module NetworkServices
  # Sends a pre-order OTP through the yourwishlist.co.in Shopify app-proxy
  # (codflow) endpoint by shelling out to `curl`, mirroring the browser call:
  #
  #   NetworkServices::YourwishlistOtpSendService.call('+916295529286')
  #
  # Returns a Hash: { success:, status:, body:, error: }. Only the phone
  # number varies per call — every other header is fixed to match a real
  # storefront request so the proxy accepts it.
  class YourwishlistOtpSendService < ApplicationService
    ENDPOINT = 'https://www.yourwishlist.co.in/apps/codflow?action=otp-send'
    ORIGIN   = 'https://www.yourwishlist.co.in'
    REFERER  = 'https://www.yourwishlist.co.in/products/game-console-m15-plus'
    USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ' \
                 'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36'
    TIMEOUT_SECONDS = 20

    # Storefront session cookie captured from a real browser request. Expires,
    # so prefer overriding via ENV['YOURWISHLIST_OTP_COOKIE'] or the `cookie:`
    # arg; this is only the fallback default.
    DEFAULT_COOKIE = 'localization=IN; _shopify_y=7e216350-ecfa-452e-bd36-a639ab4488ff; _fbp=fb.2.1783938696762.417431474466888738; _shopify_analytics=:AZ9bB-UOAAEAKxPVfdB_z22hB-pg2tcVtg6g4vJ9KXF0nIimMdRcW_clTRGvLlSI9hClvt9zT2dW2mENd94sEGQIol02t9VISC0WAPjOtFyQii_q5aK5xToXdeMw6mLfx8tQP5k0dGcDoJDfTwFL2DtQEgFslr-CaXtTSrvTol_SblHOPydHXriR1UzaKukXTVN1wVUtNUZXhhDhPQ:; _shopify_marketing=:AZ9bB-UOAAEAwYCI8y5RAotGj2APV_0seACpS-gZAqFu3lS5gPwCAykPygM7gSKLCRQffLxhZ747Jju6lX_mqzwpurZ8i5wKg6SW-6hPl2Ta5qPfxiv_6biRSBv6T_uEjf9w4-4YCLLCGUSK35utI6x3MmCGmdxaCneLkF1q9DKIRH_f9I4sRHb4qDRZ:; _shopify_s=1dc24400-e798-4b9f-b774-4dd2828d8835; _shopify_essential=:AZ9bB-T2AAEA-5anvOvtd6kNIXC9W3KqjXsUXzlPv2H4rkhVQn6sWPubwDLcuE6mvmHg11Kk1_3itBrRu-rsQvc_sAy_e6W12H3d4V8oEvW_r7tFxmnYGBRXylJHCGGILlzsb1wwhRD9bHOZDl1AQcdSyB0vu3HXUfNZ_TQHN75RGjWCr4pmDBPoIyk7puxXewQ3886a3kk2siaBT8KXGphKFLXWS7eO8-L9oKCpbl-c1lc8tjepcW_7AaI3i8AGEYX1YGUn98YCKNt3u0Gasy9_o9M-yETReZmLcygdVYm4namm0OmTlCT2nhviQfMmwRUg8hphklLq6S6Uv7-YQysjn-KcTk4dTcVsY4p2Rd07BKXJ66eJLBTK_3knJ_xUJjsg24j0ilF86s6ykOdhu3pndS3rjb1g2TAadVfY5GwfUGmN0HFwS38BqObc-plMEFf4h1zB4vOkOPtzFLiPvZIDo1uCjEKIPqzkyyfGzkA4F_RsFtmR2kRzNVo1WmoeEScM-dsdiPejoBLHlKuiKzZExIX9TvKWtcPTvKlNniUgrDmqDWgllLiT5-b2Y9FGz3dbAODr34QDbKIHbaQ5UDQFspDwiLT-CzNJLk_IWCeJG9T6hEBeq7TL4ba5WsINhWxKYZyqv9FZZXWqFj_c9tzfIIR0wEsB5AVLbRzGLnR4_lAb1VFasKj7dCDD5q9DGiv5m2SrVawnhS9FHCMGeCvA0jU70BcUx9CPPQHnsSS_3w:; _shopify_y=7e216350-ecfa-452e-bd36-a639ab4488ff'

    def initialize(phone, cookie: nil)
      @phone  = phone.to_s.strip
      # Storefront session cookie; override per environment via ENV so we don't
      # depend on the baked-in default session, which expires.
      @cookie = cookie.presence || ENV['YOURWISHLIST_OTP_COOKIE'].presence || DEFAULT_COOKIE
    end

    def call
      return failure('phone is required') if @phone.blank?

      stdout, stderr, status = Open3.capture3(*curl_args)
      return failure("curl failed: #{stderr.presence || "exit #{status.exitstatus}"}") unless status.success?

      # -w appends "\n<HTTP_CODE>" so we can split the body from the status
      # without a second request.
      body, _, http_code = stdout.rpartition("\n")
      http_code = http_code.to_i
      parsed = safe_json(body)

      {
        success: http_code.between?(200, 299),
        status: http_code,
        body: parsed || body,
        error: http_code.between?(200, 299) ? nil : "HTTP #{http_code}"
      }
    rescue StandardError => e
      failure(e.message)
    end

    private

    def curl_args
      args = [
        'curl', '--silent', '--show-error',
        '--max-time', TIMEOUT_SECONDS.to_s,
        '--location', ENDPOINT,
        '--write-out', "\n%{http_code}",
        '--header', 'accept: */*',
        '--header', 'accept-language: en-US,en;q=0.9,nl;q=0.8',
        '--header', 'content-type: application/json',
        '--header', "origin: #{ORIGIN}",
        '--header', 'priority: u=1, i',
        '--header', "referer: #{REFERER}",
        '--header', 'sec-ch-ua: "Google Chrome";v="149", "Chromium";v="149", "Not)A;Brand";v="24"',
        '--header', 'sec-ch-ua-mobile: ?0',
        '--header', 'sec-ch-ua-platform: "macOS"',
        '--header', 'sec-fetch-dest: empty',
        '--header', 'sec-fetch-mode: cors',
        '--header', 'sec-fetch-site: same-origin',
        '--header', "user-agent: #{USER_AGENT}"
      ]
      args += ['--header', "Cookie: #{@cookie}"] if @cookie.present?
      args += ['--data', { phone: @phone }.to_json]
      args
    end

    def safe_json(str)
      JSON.parse(str)
    rescue JSON::ParserError
      nil
    end

    def failure(message)
      { success: false, status: nil, body: nil, error: message }
    end
  end
end
