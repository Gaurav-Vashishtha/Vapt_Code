# WS1 → `config/routes.rb` (owner: WS3 / integrator)

Source: ARCHITECTURE.md J.3. Internal admin (Administrate) for the COD Form module.

## Where

Inside the existing `namespace :admin do … end` block (`config/routes.rb:37`), anywhere before its
`root to:` line (if the block has one) — for example directly after
`resources :sms_provider_country_mappings, except: [:destroy]`.

## Exact text to insert

```ruby
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
```

## Result

| URL | Controller | Model | Dashboard |
| --- | --- | --- | --- |
| `/admin/cod_form/plan_limits` | `Admin::CodForm::PlanLimitsController` | `CodForm::PlanLimit` | `CodForm::PlanLimitDashboard` |
| `/admin/cod_form/country_groups` | `Admin::CodForm::CountryGroupsController` | `CodForm::CountryGroup` | `CodForm::CountryGroupDashboard` |
| `/admin/cod_form/feature_gates` | `Admin::CodForm::FeatureGatesController` | `CodForm::FeatureGate` | `CodForm::FeatureGateDashboard` |
| `/admin/cod_form/global_settings` | `Admin::CodForm::GlobalSettingsController` | `CodForm::GlobalSetting` | `CodForm::GlobalSettingDashboard` |
| `/admin/cod_form/shop_configs` | `Admin::CodForm::ShopConfigsController` | `CodForm::ShopConfig` | `CodForm::ShopConfigDashboard` |
| `/admin/cod_form/order_usages` | `Admin::CodForm::OrderUsagesController` | `CodForm::OrderUsage` | `CodForm::OrderUsageDashboard` |
| `/admin/cod_form/admin_audits` | `Admin::CodForm::AdminAuditsController` | `CodForm::AdminAudit` | `CodForm::AdminAuditDashboard` |

## Navigation / registration

Nothing else to register. Administrate (0.20.1) builds the sidebar from the routes of the `admin`
namespace (`Administrate::Namespace#resources_with_index_route`), and this app does not override
`app/views/admin/application/_navigation.html.erb`, so the seven entries appear automatically
(labelled "Plan Limits", "Country Groups", …) once the routes are merged. Administrate resolves
`admin/cod_form/plan_limits` to `CodForm::PlanLimit` / `CodForm::PlanLimitDashboard` on its own.

Do **not** add these resources at the top level of `namespace :admin` (e.g. `resources :global_settings`
already exists there for the unrelated `::GlobalSetting` model).

## Check after merging (real environment)

```
bin/rails routes -g admin/cod_form
```

then open `/admin/cod_form/global_settings` — the seeded singleton row must be listed.
