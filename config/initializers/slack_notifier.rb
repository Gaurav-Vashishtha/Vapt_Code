require 'slack-notifier'

module SlackNotifier
  # Null object so a missing or revoked webhook degrades to a logged no-op
  # instead of raising inside install / uninstall / billing jobs.
  class NullNotifier
    def initialize(env_key)
      @env_key = env_key
    end

    def ping(*_args, **_kwargs)
      Rails.logger.warn("[SlackNotifier] #{@env_key} is not set; skipping Slack notification")
      nil
    end
  end

  def self.build(env_key, &block)
    url = ENV.fetch(env_key, nil)
    return NullNotifier.new(env_key) if url.nil? || url.strip.empty?

    Slack::Notifier.new(url, &block)
  end

  CLIENT = build('SLACK_WEBHOOK') do
    defaults channel: "##{ENV.fetch("SLACK_CHANNEL", nil)}", username: "#{ENV.fetch("SLACK_USERNAME", nil)}"
  end

  # Installs / uninstalls / billing notifications. The webhook URL used to be
  # hard-coded at five call sites; it now comes from the environment only.
  INSTALLS_CLIENT = build('SLACK_INSTALLS_WEBHOOK')
end
