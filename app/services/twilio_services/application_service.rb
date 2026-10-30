module TwilioServices
  class ApplicationService < ApplicationService
    def self.call(*args, &block)
      client = Twilio::REST::Client.new
      args.unshift(client)
      new(*args, &block).call
    end
  end
end
