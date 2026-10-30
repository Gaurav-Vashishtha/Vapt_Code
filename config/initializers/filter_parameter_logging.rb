# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from the log file.
Rails.application.config.filter_parameters += [:password]

# Meta advanced-matching identifiers arrive raw from the web pixel and are hashed in
# MetaEvents::EventBuilder — but Rails logs the request params before any of that runs.
# Anchored so short keys like `st` can't also redact `status` / `store_front_token`.
Rails.application.config.filter_parameters += [
  /\A(em|ph|ph_country|fn|ln|ct|st|zp|country|external_id)\z/,
]

# COD Form (docs/cod-form/ARCHITECTURE.md D.0.2): buyer contact data, session tokens and OTP codes
# never reach the log. Anchored like the list above so e.g. `otp` cannot also redact
# `otp_wait_time`, nor `token` redact `store_front_token`; nested keys (shipping_address[phone],
# buyer_identity[email], contact[phone]) are matched by their own name.
Rails.application.config.filter_parameters += [
  /\A(phone|email|address1|address2|first_name|last_name|zip|token|otp|preview_token|recovery_token)\z/,
]
