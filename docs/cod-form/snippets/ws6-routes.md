# WS6 — admin routes for `config/routes.rb` (owner WS3 merges)

Identical to ARCHITECTURE.md D.16. All controllers listed exist under `app/controllers/cod_form_admin/`.

```ruby
scope '/cod_form', module: 'cod_form_admin', as: 'cod_form_admin' do
  get  'bootstrap', to: 'bootstrap#show'
  get  'setup', to: 'setup#show'
  put  'setup', to: 'setup#update'
  post 'mode',  to: 'setup#mode'
  post 'setup/refresh_embed', to: 'setup#refresh_embed'
  post 'setup/test_order',    to: 'setup#test_order'
  get  'button', to: 'buttons#show'
  put  'button', to: 'buttons#update'
  get  'forms/defaults', to: 'forms#defaults'
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
  get 'analytics/breakdown',  to: 'analytics#breakdown'
  get 'analytics/export',     to: 'analytics#export', defaults: { format: :csv }
  get 'usage', to: 'usage#show'
end
```

Public (no auth), per D.13 tail — outside the scope above:

```ruby
get '/cod_form/preview_frame', to: 'cod_form_admin/preview_frames#show'
get '/cod_form/google/callback', to: 'cod_form_admin/google_oauth#callback'
```

Note: `forms/defaults` must stay ABOVE `resources :forms` (otherwise it matches `forms#show` with id=defaults).

## Page routes (HTML shell for the React app)

Inside the `settings_pages` lambda (`config/routes.rb:741`), so they exist bare and under `/settings-hub`:

```ruby
get '/features/cod-form(/*section)', to: 'home#index', format: false
get '/integrations/tiktok',         to: 'home#index'
get '/integrations/google-sheets',  to: 'home#index'
get '/integrations/form-pixels',    to: 'home#index'
```

Outside the lambda, next to the other `/usage-analytics/*` lines (`config/routes.rb:732-737`):

```ruby
get '/usage-analytics/cod-form', to: 'usage_analytics#index'
```
