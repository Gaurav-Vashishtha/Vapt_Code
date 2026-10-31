require 'platform-api'
module SidekiqJobs

    class RestartAppJob < ActiveJob::Base
    queue_as :restarts

    class Dyno
        attr_accessor :type
        attr_accessor :name
        attr_accessor :state

        def self.connection
        if ENV.fetch("RESTART_API_KEY", nil)
            @@connection ||= PlatformAPI.connect_oauth(ENV.fetch("RESTART_API_KEY", nil))
        end
        end

        def self.dynos
        connection.dyno.list(ENV.fetch("APP_NAME", nil)).map do |dyno_info|
            Dyno.new(dyno_info)
        end
        end

        def self.running_web_dynos
        dynos.select { |dyno| dyno.web? && dyno.up? }
        end

        def web?
        type == 'web'
        end

        def up?
        state == 'up'
        end

        def connection
        self.class.connection
        end

        def restart!
        connection.dyno.restart(ENV.fetch("APP_NAME", nil), name)
        end

        def initialize(info)
        self.type = info['type']
        self.name = info['name']
        self.state = info['state']
        end
    end

    def perform(*args)
        if Dyno.connection
        Dyno.running_web_dynos.each do |dyno|
            dyno.restart!
            sleep(2.minutes)
        end
        end
    end
    end
end