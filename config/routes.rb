require 'sidekiq/web'
require 'sidekiq/cron/web'

Sidekiq::Web.use Rack::Auth::Basic do |username, password|
  username == ENV['ADMIN_USER'] && password == ENV['ADMIN_PASS']
end

Rails.application.routes.draw do
  resources :locks
  resources :persisted_settings
  mount LetterOpenerWeb::Engine, at: '/letter_opener' if Rails.env.development?

  mount Sidekiq::Web => '/sidekiq'

  resources :lead_collections, only: [:new, :create]

  # Serve websocket cable requests in-process
  # mount ActionCable.server => '/cable'

  # view cache
  if ENV['MOUNT_RAILS_WEB_CACHE'] == 'true'
    mount RailsWebCache::Engine => '/rails_web_cache'
  end

  namespace :api do
    namespace :v1 do
      resources :events, only: [] do
        collection do
          post :track
          get :stats
        end
      end
    end
  end

  # Administrate routes.
  namespace :admin do
    resources :shops ,  except: [:destroy]
    resources :settings ,  except: [:destroy]
    resources :plans,  except: [:destroy]
    resources :order_confirmations,  except: [:destroy]
    resources :pre_order_otps,  except: [:destroy]
    resources :twilio_pricings,  except: [:destroy]
    resources :cod_king_stats,  except: [:destroy]
    resources :uninstalled_shops,  except: [:destroy]
    resources :headers,  except: [:destroy]
    resources :provinces
    resources :customers,  except: [:destroy]
    resources :customer_addresses,  except: [:destroy]
    resources :customer_shop_mappings,  except: [:destroy]
    resources :branded_whatsapp_templates,  except: [:destroy]
    resources :abandoned_carts,  except: [:destroy]
    resources :abandon_cart_schedules,  except: [:destroy]
    resources :customer_logins,  except: [:destroy]
    resources :partial_rule_sets,  except: [:destroy]
    resources :partial_product_mappings,  except: [:destroy]
    resources :wallets,  except: [:destroy]
    resources :twilio_logs,  except: [:destroy]
    resources :notification_templates
    resources :notification_logs
    resources :customer_pull_job_queues, only: [:index, :show]
    resources :job_locks, only: [:index, :show, :destroy]
    resources :unsubscribed_emails, only: [:index, :show, :destroy]
    
    resources :referral_earnings, only: [:index, :show, :destroy]
    resources :referral_shops, only: [:index, :show, :destroy]
    resources :payout_earnings, only: [:index, :show, :destroy]
    resources :referral_partners, only: [:index, :show, :destroy]
    resources :callback_requests, only: [:index, :show, :destroy]
    resources :whatsapp_number_integration_requests, only: [:index, :show, :destroy]
    resources :whatsapp_accounts, only: %i[index show edit update]
    resources :whatsapp_templates, only: %i[index show edit update destroy]
    resources :whatsapp_template_bindings, only: %i[index show edit update destroy]
    resources :whatsapp_message_logs, only: %i[index show]
    resources :sms_provider_country_mappings, except: [:destroy]
    resources :shop_charge_overrides # per-shop WhatsApp utility / marketing charge multipliers (DynamicChargeJob)
    resources :country_plan_offers # country-wise plan price / free-trial offers (PlansController#upgrade)
    resources :country_plan_offer_redemptions, only: %i[index show]
    resources :additional_settings
    # COD Form internal admin (docs/cod-form/ARCHITECTURE.md J.3)
    namespace :cod_form do
      resources :plan_limits
      resources :country_groups
      resources :feature_gates
      resources :global_settings, only: %i[index show edit update]
      resources :shop_configs,   only: %i[index show edit update]     # editable: module_access, feature_overrides, storefront_mode
      resources :order_usages,   only: %i[index show]
      resources :admin_audits,   only: %i[index show]
    end
    resources :sms_template_type_configs, except: [:destroy]
    resources :global_settings, except: [:destroy]

    # RTO intelligence dashboards
    resources :shop_domains, except: [:destroy]
    resources :rto_orders, except: [:destroy]
    resources :rto_order_events, except: [:destroy]
    resources :customer_identities, except: [:destroy]
    resources :global_customer_stats, except: [:destroy]
    resources :global_zip_stats, except: [:destroy]


    root to: 'shops#index'
  end

  # Referral System Admin (separate from main admin)
  namespace :referral_admin do
    resources :partners, controller: 'referral_partners' do
      member do
        patch :toggle_active
        get :verify_account
        post :create_payout
        post :fetch_real_earnings_last_30_days
        patch :update_notes
      end
    end
  end

  namespace :referral_admin do
    resources :referral_partners
  end

  namespace :whatsapp_admin do
    # Dashboard
    get 'whatsapp_approvals', to: 'whatsapp_approvals#index', as: :whatsapp_approvals
    
    # Refresh
    post 'whatsapp_approvals/refresh', to: 'whatsapp_approvals#refresh', as: :refresh_whatsapp_approvals
    
    # Approve/Reject with shop_domain as query parameter instead of URL parameter
    post 'whatsapp_approvals/approve', to: 'whatsapp_approvals#approve', as: :approve_whatsapp_approval
    post 'whatsapp_approvals/reject', to: 'whatsapp_approvals#reject', as: :reject_whatsapp_approval
  end

  # Referral System Routes
  get 'referral/signup', to: 'referral_registrations#new', as: 'referral_signup'
  post 'referral/signup', to: 'referral_registrations#create'

  get 'referral/login', to: 'referral_sessions#new', as: 'referral_login'
  post 'referral/login', to: 'referral_sessions#create'
  get 'referral/logout', to: 'referral_sessions#destroy', as: 'referral_logout'
  
  get 'referral/dashboard', to: 'referral_dashboard#index', as: 'referral_dashboard'
  post 'referral/sync', to: 'referral_dashboard#sync_earnings', as: 'referral_sync'
  get 'referral/sync', to: 'referral_dashboard#sync_earnings', as: 'referral_sync_get'

  get 'referral/account', to: 'referral_account#show', as: 'referral_account'
  get 'referral/account/password/edit', to: 'referral_account#edit_password', as: 'edit_referral_password'
  patch 'referral/account/password', to: 'referral_account#update_password', as: 'update_referral_password'
  get 'referral/account/details/edit', to: 'referral_account#edit_account_details', as: 'edit_referral_account_details'
  patch 'referral/account/details', to: 'referral_account#update_account_details', as: 'update_referral_account_details'

  get 'referral/earnings', to: 'referral_earnings#index', as: 'referral_earnings'
  get 'referral/earnings/summary', to: 'referral_earnings#summary', as: 'referral_earnings_summary'
  get 'referral/payouts', to: 'referral_payouts#index', as: 'referral_payouts'
  get 'referral/payouts/:id', to: 'referral_payouts#show', as: 'referral_payout'

  get 'support_dashboard', to: 'support_dashboard#index'
  get 'support_dashboard/active_stores_count', to: 'support_dashboard#active_stores_count', as: :support_dashboard_active_stores_count
  get 'support_dashboard/onboarding_funnel', to: 'support_dashboard#onboarding_funnel', as: :support_dashboard_onboarding_funnel
  get 'support_dashboard/verify_setup', to: 'support_dashboard#verify_setup'
  match 'support_dashboard/reprocess_partial_order', to: 'support_dashboard#reprocess_partial_order', via: %i[get post], as: :support_dashboard_reprocess_partial_order
  get 'support_dashboard/gst_invoice', to: 'support_dashboard#gst_invoice', as: :support_dashboard_gst_invoice
  get 'support_dashboard/support_lead_queue', to: 'support_dashboard#support_lead_queue', as: :support_dashboard_support_lead_queue
  patch 'support_dashboard/support_lead_queue/shops/:shop_id', to: 'support_dashboard#update_support_lead_tracking', as: :support_dashboard_update_support_lead_tracking
  post 'support_dashboard/support_lead_queue/shops/:shop_id/close', to: 'support_dashboard#close_support_lead', as: :support_dashboard_close_support_lead
  post 'support_dashboard/support_lead_queue/shops/:shop_id/reopen', to: 'support_dashboard#reopen_support_lead', as: :support_dashboard_reopen_support_lead
  get 'support_dashboard/uninstalled', to: 'support_dashboard#uninstalled'
  get 'support_dashboard/churn', to: 'support_dashboard#churn', as: :support_dashboard_churn
  get 'support_dashboard/churn.csv', to: 'support_dashboard#churn', defaults: { format: 'csv' }
  post 'support_dashboard/churn/sync', to: 'support_dashboard#churn_sync', as: :support_dashboard_churn_sync
  get 'support_dashboard/churn/sync_status', to: 'support_dashboard#churn_sync_status', as: :support_dashboard_churn_sync_status
  get 'support_dashboard/churn_feedback', to: 'support_dashboard#churn_feedback', as: :support_dashboard_churn_feedback
  get 'support_dashboard/risk_customers', to: 'support_dashboard#risk_customers', as: :support_dashboard_risk_customers
  post 'support_dashboard/risk_customers/load', to: 'support_dashboard#risk_customers_load', as: :support_dashboard_risk_customers_load
  get 'uninstall_survey/:token', to: 'uninstall_surveys#show', as: :uninstall_survey
  post 'uninstall_survey/:token', to: 'uninstall_surveys#create'
  get 'support_dashboard/settings_enabled', to: 'support_dashboard#settings_enabled'
  get 'support_dashboard/otp_campaign', to: 'support_dashboard#otp_campaign', as: :support_dashboard_otp_campaign
  get 'support_dashboard/feature_shops', to: 'support_dashboard#feature_shops', as: :support_dashboard_feature_shops
  get 'support_dashboard/whatsapp_retries', to: 'whatsapp_reattempts_dashboard#index', as: :support_dashboard_whatsapp_retries
  # WhatsApp languages: default-number template translations + onboarding language per country
  get 'support_dashboard/whatsapp_languages', to: 'whatsapp_template_translations_dashboard#index', as: :support_dashboard_whatsapp_languages
  post 'support_dashboard/whatsapp_languages/refresh', to: 'whatsapp_template_translations_dashboard#refresh', as: :support_dashboard_whatsapp_languages_refresh
  post 'support_dashboard/whatsapp_languages/sync_statuses', to: 'whatsapp_template_translations_dashboard#sync_statuses', as: :support_dashboard_whatsapp_languages_sync_statuses
  post 'support_dashboard/whatsapp_languages/draft_all', to: 'whatsapp_template_translations_dashboard#draft_all', as: :support_dashboard_whatsapp_languages_draft_all
  get 'support_dashboard/whatsapp_languages/bulk_review', to: 'whatsapp_template_translations_dashboard#bulk_review', as: :support_dashboard_whatsapp_languages_bulk_review
  post 'support_dashboard/whatsapp_languages/bulk_submit', to: 'whatsapp_template_translations_dashboard#bulk_submit', as: :support_dashboard_whatsapp_languages_bulk_submit
  post 'support_dashboard/whatsapp_languages/countries', to: 'whatsapp_template_translations_dashboard#save_country_language', as: :support_dashboard_whatsapp_country_languages
  delete 'support_dashboard/whatsapp_languages/countries/:id', to: 'whatsapp_template_translations_dashboard#destroy_country_language', as: :support_dashboard_whatsapp_country_language
  get 'support_dashboard/whatsapp_languages/:id/edit', to: 'whatsapp_template_translations_dashboard#edit', as: :edit_support_dashboard_whatsapp_language
  patch 'support_dashboard/whatsapp_languages/:id', to: 'whatsapp_template_translations_dashboard#update', as: :support_dashboard_whatsapp_language
  post 'support_dashboard/whatsapp_languages/:id/draft', to: 'whatsapp_template_translations_dashboard#draft', as: :support_dashboard_whatsapp_language_draft
  post 'support_dashboard/whatsapp_languages/:id/submit', to: 'whatsapp_template_translations_dashboard#submit', as: :support_dashboard_whatsapp_language_submit
  post 'support_dashboard/whatsapp_retries/run_now', to: 'whatsapp_reattempts_dashboard#run_now', as: :support_dashboard_whatsapp_retries_run_now
  get 'support_dashboard/callbacks', to: 'support_dashboard#callbacks'
  patch 'support_dashboard/callbacks/:id/resolve', to: 'support_dashboard#resolve_callback_request', as: 'resolve_support_dashboard_callback_request'
  get 'support_dashboard/whatsapp_integration_requests', to: 'support_dashboard#whatsapp_integration_requests', as: 'support_dashboard_whatsapp_integration_requests'
  patch 'support_dashboard/whatsapp_integration_requests/:id/update_status', to: 'support_dashboard#update_whatsapp_integration_status', as: 'update_whatsapp_integration_status'
  get 'support_dashboard/sms_template_approvals', to: 'support_dashboard#sms_template_approvals', as: 'support_dashboard_sms_template_approvals'
  patch 'support_dashboard/sms_template_approvals/:id/review', to: 'support_dashboard#review_sms_template_approval', as: 'support_dashboard_review_sms_template_approval'
  get 'support_dashboard/followups', to: 'support_dashboard#followups'
  get 'support_dashboard/paid_followups', to: 'support_dashboard#paid_followups'
  get 'support_dashboard/call_calendar', to: 'call_calendar#index', as: :support_dashboard_call_calendar
  get 'support_dashboard/call_calendar/calendar', to: 'call_calendar#calendar', as: :support_dashboard_call_calendar_month
  get 'support_dashboard/call_calendar/export', to: 'call_calendar#export', as: :call_calendar_export, defaults: { format: 'xlsx' }
  match 'support_dashboard/call_calendar/build', to: 'call_calendar#build_now', as: :call_calendar_build, via: %i[get post]
  post 'support_dashboard/call_calendar/top_up', to: 'call_calendar#top_up', as: :call_calendar_top_up
  post 'support_dashboard/call_calendar/get_next', to: 'call_calendar#get_next', as: :call_calendar_get_next
  post 'support_dashboard/call_calendar/outcome', to: 'call_calendar#log_outcome', as: :call_calendar_outcome
  post 'support_dashboard/call_calendar/comment', to: 'call_calendar#add_comment', as: :call_calendar_comment
  post 'support_dashboard/call_calendar/reminder', to: 'call_calendar#set_reminder', as: :call_calendar_reminder
  post 'support_dashboard/call_calendar/reminder/:id/complete', to: 'call_calendar#complete_reminder', as: :call_calendar_reminder_complete
  post 'support_dashboard/call_calendar/suppress', to: 'call_calendar#suppress', as: :call_calendar_suppress
  post 'support_dashboard/call_calendar/skip/:id', to: 'call_calendar#skip', as: :call_calendar_skip
  post 'support_dashboard/call_calendar/demo', to: 'call_calendar#create_demo', as: :call_calendar_demo
  post 'support_dashboard/call_calendar/demo/:id', to: 'call_calendar#update_demo', as: :call_calendar_demo_update
  get 'mwa/callback', to: 'merchant_whatsapp_links#callback', as: :mwa_callback
  get 'mwa/chat', to: 'merchant_whatsapp_links#chat', as: :mwa_chat
  get 'support_dashboard/merchant_whatsapp', to: 'merchant_whatsapp#index', as: :merchant_whatsapp
  get 'support_dashboard/merchant_whatsapp/sender', to: 'merchant_whatsapp#sender', as: :merchant_whatsapp_sender
  post 'support_dashboard/merchant_whatsapp/sender', to: 'merchant_whatsapp#save_sender'
  get 'support_dashboard/merchant_whatsapp/templates', to: 'merchant_whatsapp#templates', as: :merchant_whatsapp_templates
  post 'support_dashboard/merchant_whatsapp/templates', to: 'merchant_whatsapp#save_template', as: :merchant_whatsapp_save_template
  post 'support_dashboard/merchant_whatsapp/templates/create_meta', to: 'merchant_whatsapp#create_meta_template', as: :merchant_whatsapp_create_meta_template
  post 'support_dashboard/merchant_whatsapp/templates/:id/mapping', to: 'merchant_whatsapp#update_template_mapping', as: :merchant_whatsapp_template_mapping
  post 'support_dashboard/merchant_whatsapp/templates/sync', to: 'merchant_whatsapp#sync_templates', as: :merchant_whatsapp_sync_templates
  post 'support_dashboard/merchant_whatsapp/templates/:id/test', to: 'merchant_whatsapp#test_template', as: :merchant_whatsapp_test_template
  get 'support_dashboard/merchant_whatsapp/rule', to: 'merchant_whatsapp#rule_form', as: :merchant_whatsapp_rule_form
  post 'support_dashboard/merchant_whatsapp/rule', to: 'merchant_whatsapp#save_rule', as: :merchant_whatsapp_save_rule
  post 'support_dashboard/merchant_whatsapp/rule/:id/toggle', to: 'merchant_whatsapp#toggle_rule', as: :merchant_whatsapp_toggle_rule
  get 'support_dashboard/merchant_whatsapp/queue', to: 'merchant_whatsapp#queue', as: :merchant_whatsapp_queue
  get 'support_dashboard/merchant_whatsapp/reports', to: 'merchant_whatsapp#reports', as: :merchant_whatsapp_reports
  post 'support_dashboard/merchant_whatsapp/run_scheduler', to: 'merchant_whatsapp#run_scheduler', as: :merchant_whatsapp_run_scheduler
  get 'support_dashboard/engagement', to: 'engagement_dashboard#index', as: 'engagement_dashboard'
  namespace :support_dashboard do
    resources :scheduled_reports, only: %i[index new create edit update] do
      member do
        get :test_deliver
        post :send_test_deliver
      end
    end
    resources :scheduled_report_deliveries, only: %i[index]

    # rrweb session replay of onboarding / first session (2-day retention).
    resources :session_recordings, only: %i[index show] do
      member do
        get :events
      end
    end
  end
  get 'support_dashboard/followups/new_custom', to: 'support_dashboard#new_custom_follow_up', as: 'new_custom_follow_up'
  post 'support_dashboard/followups/create_custom', to: 'support_dashboard#create_custom_follow_up', as: 'create_custom_follow_up'
  
  patch 'support_dashboard/:id/relationship_manager', to: 'support_dashboard#update_relationship_manager', as: 'support_dashboard_update_relationship_manager'
  post 'support_dashboard/uninstalled_shops/:id/follow_ups', to: 'support_dashboard#create_uninstalled_follow_up', as: 'support_dashboard_create_uninstalled_follow_up'
  post 'support_dashboard/:id/follow_ups', to: 'support_dashboard#create_follow_up', as: 'support_dashboard_follow_ups'
  patch 'support_dashboard/follow_ups/:id/resolve', to: 'support_dashboard#resolve_follow_up', as: 'resolve_support_dashboard_follow_up'
  post 'support_dashboard/follow_ups/:follow_up_id/comments', to: 'support_dashboard#create_follow_up_comment', as: 'support_dashboard_follow_up_comments'
  patch 'support_dashboard/:id/notes', to: 'support_dashboard#update_notes', as: 'support_dashboard_update_notes'
  get 'support_dashboard/:id/crisp', to: 'support_dashboard#get_crisp_url', as: 'support_dashboard_crisp'

  # Email Tool (schedule emails by rules - same design as support dashboard)
  get 'support_dashboard/email_tool', to: 'email_tool#index', as: 'email_tool'
  post 'support_dashboard/email_tool/run_now', to: 'email_tool#run_now', as: 'email_tool_run_now'
  get 'support_dashboard/email_tool/rules', to: 'email_tool#rules', as: 'email_tool_rules'
  get 'support_dashboard/email_tool/rules/new', to: 'email_tool#rules_new', as: 'email_tool_rules_new'
  post 'support_dashboard/email_tool/rules', to: 'email_tool#rules_create', as: 'email_tool_rules_create'
  post 'support_dashboard/email_tool/rules/evaluate', to: 'email_tool#rules_evaluate', as: 'email_tool_rules_evaluate'
  match 'support_dashboard/email_tool/rules/:id/evaluate', to: 'email_tool#rules_evaluate', as: 'email_tool_rule_evaluate', via: [:post, :patch, :put]
  get 'support_dashboard/email_tool/rules/:id/edit', to: 'email_tool#rules_edit', as: 'email_tool_rules_edit'
  patch 'support_dashboard/email_tool/rules/:id', to: 'email_tool#rules_update', as: 'email_tool_rules_update'
  delete 'support_dashboard/email_tool/rules/:id', to: 'email_tool#rules_destroy', as: 'email_tool_rules_destroy'
  get 'support_dashboard/email_tool/templates', to: 'email_tool#templates', as: 'email_tool_templates'
  get 'support_dashboard/email_tool/templates/new', to: 'email_tool#templates_new', as: 'email_tool_templates_new'
  post 'support_dashboard/email_tool/templates', to: 'email_tool#templates_create', as: 'email_tool_templates_create'
  get 'support_dashboard/email_tool/templates/:id/edit', to: 'email_tool#templates_edit', as: 'email_tool_templates_edit'
  patch 'support_dashboard/email_tool/templates/:id', to: 'email_tool#templates_update', as: 'email_tool_templates_update'
  delete 'support_dashboard/email_tool/templates/:id', to: 'email_tool#templates_destroy', as: 'email_tool_templates_destroy'
  get 'support_dashboard/email_tool/deliveries', to: 'email_tool#deliveries', as: 'email_tool_deliveries'
  delete 'support_dashboard/email_tool/deliveries/:id', to: 'email_tool#delivery_destroy', as: 'email_tool_delivery_destroy'
  get 'support_dashboard/email_tool/deliveries/open_stats', to: 'email_tool#delivery_open_stats', as: 'email_tool_delivery_open_stats'
  get 'support_dashboard/email_tool/templates/preview', to: 'email_tool#templates_preview', as: 'email_tool_templates_preview'

  # Public tracking endpoints (no auth) - used by open pixel and click redirects in emails
  get "email_tool/track/open/:token", to: "email_tool/track#open", as: "email_tool_track_open"
  get "email_tool/track/click/:token", to: "email_tool/track#click", as: "email_tool_track_click"

  namespace :referral_admin do
  resources :shops, only: [:index, :show] do
    member do
      patch :approve
      patch :reject
    end
  end
  
  resources :partners, controller: 'referral_partners' do
    member do
      patch :toggle_active
      patch :verify_account
      post :create_payout
    end
  end
end

namespace :referral_admin do
  resources :payouts do
    member do
      get :process_payout
      patch :cancel
      get :download_receipt
    end
    
    collection do
      get :partner_summary
      post :create_partner_payout
      post :bulk_create
      get :pending_summary
    end
  end

  resources :earnings, only: [:index, :show] do
    collection do
      get :unpaid_summary
      post :bulk_mark_paid
    end
  end
  
  resources :sync, only: [:index] do
    collection do
      post :sync_all_historical
      post :sync_all_current
      get :sync_status
    end
    
    member do
      post :sync_partner
    end
  end
end

  resources :referral_shops, path: 'referral/shops' do
    member do
      post :sync_earnings
    end
  end

  # Shopify Authenticated routes
  resources :settings, only: [:create] do
    collection do
      post :test_otp
      post :test_ivr
      post :test_payment_link
      post :create_prepaid
      post :export
      post :export_message_logs_csv
      post :get_sms_share_token
      post :save_branded_whatsapp_template
      get :test_order
      get :provinces
      get :is_cod_show_hide_enabled
      get :branded_whatsapp_templates
      get :payment_methods
      get :wallet_balance
      post :send_whatsapp_approval_request
      get :setting
      get :get_published_checkout_profile
      get :checkout_extension_editor_link
      get :product_url
      post :test_notification
      post :update_owner_phone
      post :test_operator_sms
      get :local_providers
    end
  end

  resources :headers, only: [:create] do
    collection do
    end
  end

  # Append-only onboarding funnel events (QuickOnboardingV2 wizard analytics).
  resources :onboarding_events, only: [:create]

  # rrweb chunk ingest from the embedded app's session recorder.
  post 'session_recordings/ingest', to: 'session_recordings#ingest', as: :session_recordings_ingest

  namespace :api do
    resources :callback_requests, only: [:create] do
      collection do
        get :check_availability
      end
    end

    resources :one_click_checkout_leads, only: [:create] do
      collection do
        get :eligibility
      end
    end

    resources :rabbit_express_leads, only: [:create] do
      collection do
        get :eligibility
      end
    end

    resources :whatsapp_number_integration_requests, only: [:create] do
      collection do
        get :check_availability
        get :current_status
      end
    end
    
    resources :cod_orders, only: [:create]

    # COD Form storefront API (docs/cod-form/ARCHITECTURE.md D.13). Public: signed session
    # token in the body, origin check, Rack::Attack throttles (codf/*).
    namespace :form do
      post 'session',        to: 'sessions#create'
      post 'quote',          to: 'quotes#create'
      post 'contact',        to: 'contacts#create'
      post 'otp/send',       to: 'otp#send_code'
      post 'otp/verify',     to: 'otp#verify'
      post 'orders',         to: 'orders#create'
      post 'orders/status',  to: 'orders#status'
      post 'handoff',        to: 'handoffs#create'
      post 'upsell_accept',  to: 'upsells#accept'
      post 'events',         to: 'events#create'
      get  'config',                     to: 'configs#show'
      get  'bundles',                    to: 'bundles#index'
      get  'geo/:country',               to: 'geo#show',   constraints: { country: /[A-Za-z]{2}/ }
      get  'geo/:country/postal/:code',  to: 'geo#postal', constraints: { country: /[A-Za-z]{2}/, code: /[A-Za-z0-9 \-]{2,12}/ }
    end
    # Partner billing: apply a usage charge against a shop's active subscription
    # (EASY_SELL_AUTH_TOKEN guarded, same as refresh_payment_customization).
    resources :usage_charges, only: [:create]
    # Partner billing: read a shop's active subscription (plan name + price). Same auth.
    match 'active_subscription', to: 'active_subscriptions#show', via: %i[get post]

    # RabbitPay -> CodKing: ingest a pre-order OTP row as an abandoned-cart entry.
    namespace :rabbitpay do
      post :abandoned_cart, to: "abandoned_carts#create"
    end

    post :custom_abandoned_cart, to: "custom_abandoned_carts#create"

    namespace :webhooks do
      resources :endpoints, only: %i[index create update destroy] do
        member { post :rotate_secret }
        collection do
          get  :deliveries
          post :replay
        end
      end
    end

    # Public inbound ingest. Kept last in the :api namespace so its wildcard
    # segments can never shadow a named route above it.
    post "webhooks/:provider/:endpoint_token", to: "webhooks/ingest#create", as: :webhook_ingest

    namespace :sidekick do
      resources :order_confirmations, only: [] do
        collection { post :search }
      end
      resources :pre_order_otps, only: [] do
        collection { post :search }
      end
      resource :feature_settings, only: [:show]
      resource :whatsapp_status, only: [:show], controller: 'whatsapp_status'
      resource :billing_usage, only: [:show], controller: 'billing_usage'
      resource :performance_summary, only: [:show], controller: 'performance_summary'
      resource :setup_health, only: [:show], controller: 'setup_health'
      resource :cod_rules, only: [:show], controller: 'cod_rules'
      resource :plans, only: [:show], controller: 'plans'
      resource :abandoned_carts, only: [:show], controller: 'abandoned_carts'
      resources :whatsapp_templates, only: [:index]
      resources :whatsapp_campaigns, only: %i[index show create update] do
        collection { get :options }
      end
      resources :message_logs, only: [] do
        collection { post :search }
      end
    end

    namespace :whatsapp do
      # Customer-notification language options + previews (default-number templates).
      resources :languages, only: [:index]
      resource :language, only: [:update], controller: 'languages'
      # Singular: legacy default-number connected-state + legacy disconnect.
      resource :account, only: %i[show destroy]
      # Plural: manage multiple numbers.
      resources :accounts, only: %i[index create update destroy]
      resource :phone_number, only: [] do
        get  :status
        post :register
        post :request_code
        post :verify_code
      end
      resources :templates, only: %i[index create update destroy] do
        collection { post :sync }
        member { post :meta_edit }
      end
      resources :test_messages, only: %i[create]
      resources :events, only: %i[index]
      resources :template_library, only: %i[index]
      resources :template_bindings, only: %i[index create destroy] do
        collection { get :notifications_active; post :pause }
      end
      resources :inbound_messages, only: %i[index]
      namespace :inbox do
        get  'summary', to: 'summary#show'
        get  'me',      to: 'agents#me'
        get  'reports', to: 'reports#show'
        resources :agents,    only: %i[index]
        resources :templates, only: %i[index]
        resources :conversations, only: %i[index show update] do
          member do
            post :read
            post :unread
            post :block
            post :unblock
          end
          resources :messages, only: %i[index create]
          resource  :customer, only: %i[show] do
            post :payment_link
          end
          resource  :labels, only: %i[update], controller: 'conversation_labels'
          resource  :ai, only: [], controller: 'conversation_ai' do
            post :suggest
            post :pause
            post :resume
            post :dismiss_draft
          end
        end
        resource  :settings, only: %i[show update]
        resources :saved_replies, only: %i[index create update destroy] do
          member { post :used }
        end
        resources :labels, only: %i[index create update destroy]
      end
      namespace :ai do
        resource :settings, only: %i[show update] do
          post :import_knowledge
        end
        resource :wallet, only: %i[show update]
        resources :recharges, only: %i[create] do
          collection { post :confirm }
        end
        resource :playground, only: %i[create], controller: 'playground'
        resources :runs, only: %i[index]
      end
      resources :automation_tests,  only: %i[create]
      resources :message_logs, only: %i[index] do
        member { post :retry }
      end
      scope 'attribution', controller: 'attributions', as: 'attribution' do
        get 'campaigns', action: :campaigns
        get 'campaigns/:id', action: :campaign, as: :campaign
        get 'notifications', action: :notifications
        get 'engagement', action: :engagement
      end
      resources :media_uploads, only: %i[create]
      resources :sample_product_images, only: %i[index]

      resources :campaigns, only: %i[index show create update destroy] do
        collection { get :overview }
        member do
          post :launch
          post :pause
          post :resume
          post :cancel
          post :retry_now
          post :test
          get  :report
          get  :recipients
          get  :preview
        end
      end
      resources :audiences, only: [] do
        collection { post :preview; post :estimate }
      end
      resources :campaign_recipes, only: %i[index] do
        member { post :apply }
      end
      resources :audience_imports, only: %i[create show update]
      resources :opt_outs, only: %i[index create destroy]
      resources :contacts, only: %i[index create update destroy] do
        collection do
          post :import
          post :sync
          get  :sync_status
          post :bulk_tag
          get  :meta
        end
      end
      resources :segments, only: %i[index create update destroy] do
        collection { post :preview }
      end
    end

    # Legacy (MSG91) COD-to-prepaid reminder configuration. Distinct from the
    # BSP WhatsApp namespace above — uses shop-curated templates and the
    # branded operator path.
    resources :prepaid_templates, only: %i[index]
    resource :prepaid_reminders, only: %i[show update]

    post '/razorpay_orders/create', to: 'razorpay_orders#create'
    post '/razorpay_orders/verify', to: 'razorpay_orders#verify'
    # Razorpay redirects the browser here after payment (UPI etc.); we verify and redirect back with success params
    post '/razorpay_orders/callback', to: 'razorpay_orders#callback'
    post '/tax_calculation/calculate', to: 'tax_calculation#calculate'

  end

  # Public storefront ingest for the checkout/COD form funnel (no Shopify auth).
  post '/form_funnel/ingest', to: 'form_funnel#ingest'

  # COD Form: public routes without session-token auth (ARCHITECTURE.md D.13, H.6, I.5).
  get '/cod_form/preview_frame', to: 'cod_form_admin/preview_frames#show'
  get '/cod_form/google/callback', to: 'cod_form_admin/google_oauth#callback'

  # COD Form admin API for the embedded app (ARCHITECTURE.md D.16; App Bridge session token).
  scope '/cod_form', module: 'cod_form_admin', as: 'cod_form_admin' do
    get  'bootstrap', to: 'bootstrap#show'
    get  'setup', to: 'setup#show'
    put  'setup', to: 'setup#update'
    post 'mode',  to: 'setup#mode'
    post 'setup/refresh_embed', to: 'setup#refresh_embed'
    post 'setup/test_order',    to: 'setup#test_order'
    post 'setup/dismiss_optin', to: 'setup#dismiss_optin' # Summary opt-in card (DSH-9, setup_state.dismissed_optin_at)
    get  'sync', to: 'sync#show'
    post 'sync', to: 'sync#create'
    get  'button', to: 'buttons#show'
    put  'button', to: 'buttons#update'
    get  'forms/defaults', to: 'forms#defaults' # must stay above `resources :forms`
    resources :forms, only: %i[index show create update destroy] do
      member { post :publish; post :discard_draft; post :duplicate; post :make_default }
    end
    resources :shipping_rates, only: %i[index create update destroy] do
      collection { post :reorder; post :import_csv }
    end
    resources :offers, only: %i[index show create update destroy] do
      member { post :status }
    end
    resources :ab_tests, only: %i[index show create update destroy] do
      member { post :start; post :stop }
    end
    get 'fraud', to: 'fraud#show'
    put 'fraud', to: 'fraud#update'
    resources :block_entries, only: %i[index create destroy]
    resources :rejections, only: %i[index]
    resources :pixels, only: %i[index create update destroy] do
      member { post :test }
    end
    get    'integrations', to: 'integrations#index'
    get    'integrations/google_sheets/auth_url', to: 'google_oauth#auth_url'
    get    'integrations/google_sheets/sheets',   to: 'google_oauth#sheets'
    put    'integrations/:provider', to: 'integrations#update'
    delete 'integrations/:provider', to: 'integrations#destroy'
    get 'analytics',            to: 'analytics#show'
    get 'analytics/sessions',   to: 'analytics#sessions'
    get 'analytics/breakdown',  to: 'analytics#breakdown'
    get 'analytics/export',     to: 'analytics#export', defaults: { format: :csv }
    get 'usage', to: 'usage#show'
  end

  # Meta pixel ingest from extensions/cod-king-web-pixel (no Shopify auth, per-shop token).
  post '/events/meta', to: 'meta_events#create'

  # Plans page in the sidebar. Must sit above `resources :plans`, whose index
  # would otherwise claim GET /plans (PlansController has no index action).
  get '/plans', to: 'subscription#index'

  resources :plans do
    collection do
      post :upgrade
      post :cancel
      post :usage_charge
      post :update_capped_amount
      get :opted_plan
      get :india_pricing
      get :otp_campaign
      post :apply_otp_campaign_coupon
      delete :remove_otp_campaign_coupon
    end
  end
  
  resources :twilio_logs, only: [:index]
  
  resources :jobs, only: [] do
    collection do
      post :status
    end
  end

  resources :partial_rule_sets, except: [:new, :edit] do
    collection do
      post :reorder
    end
  end

  resources :discounts, except: [:new, :edit] do
    member do
      post :activate
      post :deactivate
      post :resync
    end
    collection do
      post :validate_exceptions
    end
  end

  resources :scheduled_shop_reports, only: %i[index show update] do
    member do
      post :send_now
    end
  end

  # Message Logs route
  # Custom route for fetching Twilio logs by slug called '/message_logs'
  get '/twilio_logs/message_logs/', to: 'twilio_logs#message_logs'
  get '/twilio_logs/cod_payment_logs/', to: 'twilio_logs#cod_payment_logs'
  get '/twilio_logs/cod_payment_logs_export/', to: 'twilio_logs#cod_payment_logs_export'
  get '/twilio_logs/cod_king_abandoned_carts/', to: 'twilio_logs#cod_king_abandoned_carts'
  get '/twilio_logs/cod_king_abandoned_carts_export/', to: 'twilio_logs#cod_king_abandoned_carts_export'
  get '/analytics/summary', to: 'analytics#summary_metrics', as: :summary_analytics
  get 'analytics/fast_dashboard', to: 'analytics#fast_dashboard'
  get 'analytics/form_funnel', to: 'analytics#form_funnel'
  get 'analytics/summary_metrics', to: 'analytics#summary'  # Add this line



  get "/logs", to: "logs#index"
  get "/logs/export", to: "logs#export"

  get '/track/:shop_id/:template', to: 'notification_events#track', as: :track_notification

  get  '/webhook/whatsapp', to: 'meta_webhook#verify'
  post '/webhook/whatsapp', to: 'meta_webhook#receive'
  # MSG91 WhatsApp delivery reports (COD King account) — drives 131049 retries.
  post '/webhook/msg91/whatsapp', to: 'msg91_webhook#whatsapp'

  # ---------------------------------------------------------------------------
  # Custom-branded WhatsApp (partner-facing). Portal is gated by partner-signed
  # links (see CustomBranded::BaseController); the public API by per-shop
  # bearer keys (Api::V1::Cb::BaseController). NOTE: "branded whatsapp"
  # elsewhere in this app means the shared MSG91 number — this is the
  # merchant-own-number BSP stack exposed externally, hence the cb/ prefix.
  # Domains contain dots, so the segment needs an explicit constraint.
  # Public (unauthenticated for now) cross-brand history & stats panel.
  get '/cb-stats', to: 'custom_branded/stats#show', as: :custom_branded_stats
  get '/cb-docs/openapi.json', to: 'custom_branded/stats#openapi', as: :custom_branded_openapi

  scope '/cb/:shop_domain', module: :custom_branded, as: :custom_branded,
        constraints: { shop_domain: %r{[^/]+} } do
    get '/', to: 'portal#show', as: :portal
    # Merchant-facing page: connect a WhatsApp number and nothing else.
    get '/connect', to: 'portal#connect', as: :connect
    resources :accounts, only: %i[index create update destroy]
    resources :templates, only: %i[index create update destroy] do
      collection { post :sync }
      member { post :meta_edit }
      # Portal "Test" button: send this template to a phone with sample values.
      member { post :test, to: 'template_tests#create' }
      # Drawer "Activity" list: recent sends of this template.
      member { get :activity, to: 'template_activities#index' }
    end
    resources :api_keys, only: %i[create destroy]
    get '/events', to: 'event_templates#events', as: :events
    get '/activity', to: 'template_activities#brand', as: :activity
    resources :event_templates, only: %i[create update destroy]
  end

  namespace :api do
    namespace :v1 do
      namespace :cb do
        resources :messages, only: %i[index create show]
        resources :templates, only: %i[index create update destroy] do
          collection { post :sync }
        end
        resources :accounts, only: %i[index update destroy]
        resources :events, only: %i[index]
        resources :event_templates, only: %i[index]
        resources :brands, only: %i[index create]
        # Partner-key only: ParcelX mints/revokes per-brand keys.
        resources :keys, only: %i[index create destroy]
        # Fire a signed sample webhook at the configured partner URL.
        resources :webhook_tests, only: %i[create]
      end
    end
  end
  get "/unsubscribe", to: "unsubscribe#create"

  # Public routes
  resources :script, only: [:index, :show, :create_prepaid_link] do
    collection do
      get :settings
      post :delete_data
      get :translations
      get :script_react_new
      get :notifik
      get :notifik_svelte
      get :notifik_svelte_css
      get :widget_preview
      get :lightweight_settings
      post :post_error
    end
  end

  get "/upsells/products", to: "upsells#products"
  resource :upsell_config, only: [:show, :create]
  resource :free_gift_config, only: [:show, :create]

  resources :pricing, only: [:index] do
    collection do
      get :shopify_order_data
    end
  end
  
  get '/script_react-*.js.map', to: 'script#source_map'

  resources :order_confirmations do
    collection do
      post :confirm
      post :cancel
      post :update_ph_and_send_otp
      post :confirm_order_manually
      post :resend_message
      post :send_code_on_whatsapp
      post :pre_order_otp
      post :update_cart_details
      post :easysell_send_otp
      post :easysell_send_confirmation_sms
      post :easysell_send_ac_sms
      post :easysell_send_fulfiment_sms
      post :pre_order_otp_verify
      get :sso_check
      delete :sso_logout
      post :persistent_signin_stat
      post :refresh_payment_customization
      post :restart_web_dynos
      post :order_fulfilled
      get :prepaid
      get :create_prepaid_link
      get :redirect_to_prepaid_link
      post :review_whatsapp
      post :pending_whatsapp
      get :render_otp_box
      get :redirect_payment_link
      post :initiate_s3_backup
      post :post_shipping_address
      get :zip_details
      post :create_customer_login
      get :partial_rule_sets
      get :partial_dummy_variant_id
      get :trigger_order_confirmation
      get :trigger_partial_order_edit
      post :partial_cart
      get :get_published_checkout_profile
      get :is_cod_king_block_enabled
      get :shipping_address_count
      get :shipping_addresses
      get :country_codes
      get :pricing
      get :send_locked_capped_email
      get :config_metafields
      post :post_error_payload
      get :crisp_url
      get :create_discount_code
      # post :skip_button
    end
  end

  get '/order/verify', to: 'order_verify#index'
  get '/order/prepaid', to: 'order_confirmations#prepaid'
  get '/public/order_status', to: 'order_confirmations#public_order_status'
  post '/rto/decision', to: 'rto#decision'
  post '/is-existing-customer', to: 'existing_customers#show'
  post '/orders/bulk-verify', to: 'settings#bulk_verify'
  resources :sms_template_approvals, only: [:index, :create]
  get 'analytics/average_order_value', to: 'analytics#average_order_value'
  get 'analytics/order_type_breakdown', to: 'analytics#order_type_breakdown'
  get 'analytics/partial_payment_summary', to: 'analytics#partial_payment_summary'
  get 'analytics/summary', to: 'analytics#summary_analytics'
  get 'analytics/communication_summary', to: 'analytics#communication_summary'
  get 'analytics/communication_summary_overall', to: 'analytics#communication_summary_overall'
  get 'analytics/daily_sales_by_order_type', to: 'analytics#daily_sales_by_order_type'
  get 'analytics/overall_cod_vs_prepaid_value', to: 'analytics#overall_cod_vs_prepaid_value'
  get 'analytics/daily_order_count', to: 'analytics#daily_order_count'
  get 'analytics/daily_total_sales', to: 'analytics#daily_total_sales'
  get '/subscription', to: 'subscription#index'
  get '/billing/usage_summary', to: 'billing#usage_summary'
  get '/billing/referral_link', to: 'billing#referral_link_status'
  post '/billing/referral_link', to: 'billing#apply_referral_code'
  delete '/billing/referral_link', to: 'billing#unlink_referral_code'
  get '/help-and-support', to: 'help_and_support#index'
  get '/usage-analytics', to: 'usage_analytics#index'
  get '/usage-analytics/order-logs', to: 'usage_analytics#index'
  get '/usage-analytics/message-logs', to: 'usage_analytics#index'
  get '/usage-analytics/usage-logs', to: 'usage_analytics#index'
  get '/usage-analytics/branded-notifications', to: 'usage_analytics#index'
  get '/usage-analytics/cod-king-abandoned-carts', to: 'usage_analytics#index'
  get '/usage-analytics/cod-form', to: 'usage_analytics#index' # COD Form analytics tab
  get '/usage-analytics/orders', to: 'usage_analytics#index'
  get '/order_stats/summary', to: 'order_stats#summary'
  get '/order_stats/orders', to: 'order_stats#orders'
  # Settings screens. The React app shows them under /settings-hub in the
  # address bar so the admin nav highlights Settings, so each one is routed
  # both bare and under that prefix to the same controller.
  settings_pages = lambda do
    get '/billing', to: 'billing#index'
    get '/networks', to: 'networks#index'
    get '/features', to: 'features#index'
    get '/features/otp', to: 'otp#index'
    get '/features/otp/pre-order', to: 'otp#index'
    get '/features/otp/pre-order/ui', to: 'otp#index'
    get '/features/ui-customization', to: 'otp#index'
    get '/features/post-order-otp', to: 'otp#index'
    get '/features/shopify-plus-widget', to: 'otp#index'
    get '/features/otp/post-order', to: 'otp#index'
    get '/features/otp/checkout-extension', to: 'otp#index'
    get '/features/partial-payment', to: 'partial_payment#index'
    get '/features/partial-payment/add', to: 'partial_payment#index'
    get '/features/partial-payment/edit', to: 'partial_payment#index'
    get '/features/cod-show-hide', to: 'cod_show_hide#index'
    get '/features/limit-cod', to: 'cod_show_hide#index'
    get '/features/cod-to-prepaid', to: 'cod_to_prepaid#index'
    get '/features/prepaid-discount', to: 'home#index'
    get '/features/discounts', to: 'home#index'
    get '/features/cod-fees', to: 'cod_fees#index'
    get '/features/notifications', to: 'notifications#index'
    get '/features/whatsapp',            to: 'whatsapp#index'
    get '/features/whatsapp/account',    to: 'whatsapp#account'
    get '/features/whatsapp/templates',  to: 'whatsapp#templates'
    get '/features/whatsapp/logs',       to: 'whatsapp#logs'
    get '/features/whatsapp/inbox(/*section)', to: 'whatsapp#index'
    get '/features/whatsapp/replies',    to: 'whatsapp#index'
    get '/features/whatsapp/campaigns',  to: 'whatsapp#campaigns'
    get '/features/whatsapp/audience',   to: 'whatsapp#audience'
    get '/features/whatsapp-campaigns(/*section)', to: 'whatsapp#campaigns'
    get '/features/reports', to: 'home#index'

    # New admin nav section-landing pages (React app routes internally).
    get '/checkout', to: 'home#index'
    get '/checkout/address-prefill', to: 'home#index'
    get '/messaging', to: 'home#index'
    get '/post-purchase', to: 'home#index'
    get '/checkout-enhancements', to: 'home#index'
    get '/integrations', to: 'home#index'
    get '/integrations/google-ads', to: 'home#index'
    get '/integrations/pixel', to: 'home#index'

    # COD Form admin screens (ARCHITECTURE.md D.16 / H.2): the React app routes internally.
    get '/features/cod-form(/*section)', to: 'home#index', format: false
    get '/integrations/tiktok',         to: 'home#index'
    get '/integrations/google-sheets',  to: 'home#index'
    get '/integrations/form-pixels',    to: 'home#index'
  end
  settings_pages.call
  scope '/settings-hub', as: :settings_hub, &settings_pages
  get '/settings-hub(/*section)', to: 'home#index', format: false

  get '/custom_setup', to: 'home#index'
  get '/onboarding', to: 'onboarding#index'
  get '/quick-onboarding', to: 'quick_onboarding#index'
  get '/quick-onboarding/otp', to: 'quick_onboarding_otp#index'
  get '/quick-onboarding/otp/pre-order', to: 'quick_onboarding_otp#index'
  get '/quick-onboarding/otp/post-order', to: 'quick_onboarding_otp#index'
  get '/quick-onboarding/fees', to: 'quick_onboarding_cod_fees#index'
  get '/quick-onboarding/notifications', to: 'quick_onboarding_notifications#index'
  get 'quick-onboarding/billing', to: 'quick_billing#index'
  get '/quick-onboarding/limit-cod', to: 'quick_onboarding_limit_cod#index'
  get '/quick-onboarding/partial-payment', to: 'quick_onboarding_partial_payment#index'

  get 'system_dashboard', to: 'system_dashboard#index'

  resources :twillio do
    collection do
      post :ivr_webhook
      post :test_ivr_webhook
    end
  end

  # Default shopify required routes
  root to: 'home#index'
  get '/orders/bulk-verify', to: 'home#index'
  get '/check_permissions', to: 'home#check_permissions'
  post '/update_permissions', to: 'home#update_permissions'
  # First-install token mint (called by the React shell before reload).
  post '/session/bootstrap', to: 'sessions#bootstrap'
  get '/whatsapp_inbox_media/:token', to: 'whatsapp_inbox_media#show', as: :whatsapp_inbox_media
  get '/wa/r/:token', to: 'whatsapp_link_redirects#show', as: :whatsapp_link_redirect
  # Internal ops dashboard (HTTP Basic auth from ENV, see CodkOpsController)
  get '/codk-ops/api/overview', to: 'codk_ops#overview', defaults: { format: :json }
  get '/codk-ops', to: 'codk_ops#app'
  get '/codk-ops/*path', to: 'codk_ops#app', format: false
  mount ShopifyApp::Engine, at: '/'
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
end