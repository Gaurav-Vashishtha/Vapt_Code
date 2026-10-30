module NetworkServices
  # Test harness for YourwishlistOtpSendService: generates N random Indian
  # phone numbers and fires an OTP send for each, returning per-number results
  # plus a summary. For manual/QA testing only.
  #
  #   NetworkServices::YourwishlistOtpTestRunner.call            # 10 numbers
  #   NetworkServices::YourwishlistOtpTestRunner.call(count: 5)
  #   NetworkServices::YourwishlistOtpTestRunner.call(count: 3, delay: 1.0)
  #   NetworkServices::YourwishlistOtpTestRunner.call(phones: ['+919130751989'])
  class YourwishlistOtpTestRunner < ApplicationService
    DEFAULT_COUNT = 10

    def initialize(count: DEFAULT_COUNT, phones: nil, cookie: nil, delay: 0.0)
      @count  = count.to_i
      @phones = Array(phones).map(&:to_s).reject(&:blank?).presence
      @cookie = cookie
      @delay  = delay.to_f
    end

    def call
      numbers = @phones || Array.new(@count) { random_indian_phone }

      results = numbers.each_with_index.map do |phone, i|
        res = YourwishlistOtpSendService.call(phone, cookie: @cookie)
        log_response(i + 1, numbers.size, phone, res)
        sleep(@delay) if @delay.positive?
        { phone: phone }.merge(res)
      end

      succeeded = results.count { |r| r[:success] }
      {
        total: results.size,
        succeeded: succeeded,
        failed: results.size - succeeded,
        results: results
      }
    end

    private

    # Print each call's full response to the console as it completes, so you
    # see progress live rather than only the final summary.
    def log_response(index, total, phone, res)
      icon = res[:success] ? '✅' : '❌'
      body = res[:body].is_a?(String) ? res[:body] : res[:body].to_json
      puts "#{icon} [#{index}/#{total}] #{phone} -> HTTP #{res[:status] || '-'}"
      puts "   body:  #{body}"          if body.present?
      puts "   error: #{res[:error]}"   if res[:error].present?
      $stdout.flush
    end

    # E.164 India mobile: +91 then a 10-digit number starting 6-9.
    def random_indian_phone
      "+91#{[6, 7, 8, 9].sample}#{Array.new(9) { rand(10) }.join}"
    end
  end
end
