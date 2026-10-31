# ActionMailer::Base.add_delivery_method :ses, AWS::SES::Base,
#   access_key_id: ENV['AMAZON_ACCESS_KEY'],
#   secret_access_key: ENV['AMAZON_SECRET_KEY'],
#   server: 'email.us-west-2.amazonaws.com',
#   message_id_domain: 'us-west-2.amazonses.com',
#   signature_version: 4

# https://github.com/drewblas/aws-ses/issues/78#issuecomment-811270479
creds = Aws::Credentials.new(
  ENV.fetch("AWS_ACCESS_KEY", nil),
  ENV.fetch("AWS_SECRET_KEY", nil),
)

Aws::Rails.add_action_mailer_delivery_method(
  :ses,
  credentials: creds,
  region: 'us-east-1'
)