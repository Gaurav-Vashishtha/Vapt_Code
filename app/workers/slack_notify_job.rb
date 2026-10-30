class SlackNotifyJob < ApplicationJob
  sidekiq_options queue: 'administration'
  def perform(text)
    SlackNotifier::CLIENT.ping(
      text: text
    )
  end
end