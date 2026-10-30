# No Features Nudge (disabled via comment)
# template = NotificationTemplate.find_or_initialize_by(name: "no_features_nudge")
# template.assign_attributes(
#   subject: "🚨 You haven't enabled any features yet",
#   view_file: "no_features_nudge",
#   trigger_type: "no_features_enabled",
#   trigger_params: { days: 3, hour: 11 },
#   active: true
# )
# template.save! if template.changed?

template = NotificationTemplate.find_or_initialize_by(name: "billing_not_activated")
template.assign_attributes(
  subject: "Your COD King setup is incomplete – Fix in 2 minutes",
  view_file: "billing_not_activated",
  trigger_type: "billing_not_activated",
  trigger_params: { days: 5, hour: 14 },
  active: true
)
template.save! if template.changed?

template = NotificationTemplate.find_or_initialize_by(name: "no_features_enabled")
template.assign_attributes(
  subject: "Your COD King setup isn’t complete yet 🚧",
  view_file: "no_features_enabled",
  trigger_type: "no_features_enabled",
  trigger_params: { days: 2, hour: 10 },
  active: true
)
template.save! if template.changed?

template = NotificationTemplate.find_or_initialize_by(name: "prepaid_boost_case_study")
template.assign_attributes(
  subject: "See how brands are boosting prepaid orders 💰",
  view_file: "prepaid_boost_case_study",
  trigger_type: "prepaid_boost_case_study",
  trigger_params: { days: 7, hour: 13 },
  active: true
)
template.save! if template.changed?

NotificationTemplate.find_or_initialize_by(name: "billing_urgency_nudge").tap do |template|
  template.assign_attributes(
    subject: "⏳ Only 2 days left to unlock exclusive tools",
    view_file: "billing_urgency_nudge",
    trigger_type: "billing_not_activated",
    trigger_params: { days: 10, hour: 11 },
    active: true
  )
  template.save! if template.changed?
end

NotificationTemplate.find_or_initialize_by(name: "inactivity_reengagement_nudge").tap do |template|
  template.assign_attributes(
    subject: "Need help getting started with COD King?",
    view_file: "inactivity_reengagement_nudge",
    trigger_type: "no_features_enabled",
    trigger_params: { days: 15, hour: 11 },
    active: true
  )
  template.save! if template.changed?
end

NotificationTemplate.find_or_initialize_by(name: "abandoned_cart_not_enabled").tap do |template|
  template.assign_attributes(
    subject: "Recover lost orders with Abandoned Cart nudges 🛒",
    view_file: "abandoned_cart_not_enabled", # ✅ reusing the same template
    trigger_type: "abandoned_cart_not_enabled",
    trigger_params: { days: 18, hour: 11 },
    active: true
  )
  template.save! if template.changed?
end