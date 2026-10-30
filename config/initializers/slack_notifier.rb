require 'slack-notifier'

module SlackNotifier
  CLIENT = Slack::Notifier.new ENV['SLACK_WEBHOOK'] do
    defaults channel: "##{ENV['SLACK_CHANNEL']}", username: "#{ENV['SLACK_USERNAME']}"
  end
end