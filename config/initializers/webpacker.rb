forward_env_vars = [
  'APP_HOST', 'SMARTLOOK_KEY', 'CRISP_WEBSITE_ID',
   'WHATSAPP_APPROVERS_EMAIL_LIST'
]

forward_env_vars.each do |key|
  Webpacker::Compiler.env[key] = ENV[key]
end

# WEBPACKER_DEV_SERVER_HOST is added for heroku specific
# Webpacker::Compiler.env['WEBPACKER_DEV_SERVER_HOST'] = ENV['APP_HOST']
