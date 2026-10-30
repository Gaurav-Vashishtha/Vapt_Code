# app/workers/network_jobs/slack_notification_job.rb
class NetworkJobs::SlackNotificationJob
  include Sidekiq::Worker
  sidekiq_options queue: 'notifications', retry: 2

  def perform(text, identifier = 'global')
    return unless can_send?(identifier)
    
    # Parse and send to Sentry properly
    send_to_sentry(text)
    
    # Optionally still send to Slack (commented out)
    # SlackNotifier::CLIENT.ping(text: text)
    
    # Record the send
    record_send(identifier)
    
  rescue => e
    Rails.logger.error "Slack notification failed: #{e.message}"
    raise e
  end

  private

  def send_to_sentry(text)
    # Try to parse JSON payload
    error_data = parse_error_data(text)
    
    # Extract message - ALWAYS returns a string
    message = extract_message(error_data, text)
    
    # Capture as message (not exception) with rich context
    Sentry.capture_message(
      message,
      level: severity_to_level(error_data['severity']),
      extra: {
        tracking_id: error_data['trackingId'],
        operation: error_data['operation'],
        shop: error_data['shop'],
        url: error_data['url'],
        error_name: error_data.dig('error', 'name'),
        user_agent: error_data.dig('context', 'userAgent'),
        stack: error_data.dig('context', 'stack'),
        full_payload: error_data
      },
      tags: {
        shop: error_data['shop'],
        error_type: error_data.dig('error', 'name') || 'ClientError',
        operation: error_data['operation']
      }
    )
  end

  def parse_error_data(text)
    JSON.parse(text)
  rescue JSON::ParserError
    # Return hash with STRING keys for consistency
    { 'raw_message' => text }
  end

  def extract_message(error_data, fallback_text)
    # Try multiple paths to extract a meaningful message
    error_data.dig('error', 'message') ||
    error_data['raw_message'] ||
    error_data.dig('message') ||
    fallback_text.to_s.truncate(500) # Always return a string
  end

  def severity_to_level(severity)
    case severity&.downcase
    when 'error' then :error
    when 'warning', 'warn' then :warning
    when 'info' then :info
    else :error
    end
  end

  def can_send?(identifier)
    key = "slack_rate_limit:#{identifier}"
    current_count = Sidekiq.redis { |conn| conn.get(key) }.to_i
    
    # Max 10 messages per minute
    if current_count >= 10
      Rails.logger.warn "Slack rate limited for: #{identifier}"
      return false
    end
    
    true
  end

  def record_send(identifier)
    key = "slack_rate_limit:#{identifier}"
    Sidekiq.redis do |conn|
      conn.multi do |r|
        r.incr(key)
        r.expire(key, 60) # Reset after 60 seconds
      end
    end
  end
end