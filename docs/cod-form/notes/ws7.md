# WS7 — admin React screens: implementation notes

3 Oct 2026 · covers ARCHITECTURE.md section H (K.7) · everything P1 + P2 + P3 is built; optional features are switched by gates.

## 1. Files created — `app/javascript/packs/Pages/CodForm/` (103 files, about 12,700 lines)

| Area | Files |
| --- | --- |
| Entry and data layer | `CodFormApp.jsx` (path → screen switch, `ModuleDisabled` when the module is off), `api.js` (**every** admin endpoint of D.15, no `humps`), `defaults.js` (**every** config shape and default: B.1.1, B.1.2, C.1–C.6, templates fallback, English text fallback), `constants.js` (countries, locales, feature keys, limits, paths), `useCodFormBootstrap.js`, `useResource.js`, `money.js`, `utils.js`, `i18n.js` |
| `components/` | `ScreenSaveBar`, `Screen` (page frame, skeleton, load and save error banners), `Gate` (+ `UpgradeCard`, `useGate`), `ResourceTargetPicker`, `ColorField`, `LocalizedTextField`, `CountryMultiSelect`, `MoneyField`, `UsageMeter`, `EmptyState`, `ModuleDisabled`, `FormMock` (React mock of the buyer form), `PreviewFrame` (H.6 iframe), `ExpressOnlyBanner`, `LimitCodNotes`, `BillingUsageRows`, `OnboardingSetupStep` |
| `Setup/` | `SetupPage`, `ModeCard`, `EmbedStatusCard`, `ChecklistCard`, `HealthCard`, `CountriesCard`, `VisibilityCard`, `OrderTotalCard`, `TestOrderCard`, `UsageCard`, `AdvancedCard` |
| `Buttons/` | `ButtonsPage`, `PresetPicker`, `ButtonStyleCard`, `PlacementCard`, `StickyCard`, `CartButtonsCard`, `ThemeButtonsCard`, `QuantityWidgetCard`, `ButtonPreview` |
| `Designer/` | `DesignerRoute`, `DesignerPage`, `FormsListPage`, `FormTargetingCard`, `TemplatesModal`, `FieldEditor`, `CustomFieldModal`, `ContentBlockModal`, `SortableList`, `PublishBar`, `DevicePreview`, `tabs/{FieldsTab,BlocksTab,DesignTab,TextsTab,ThankYouTab}`, helpers `texts.js`, `formDefaults.js`, `fieldLabels.js` |
| `Shipping/` | `ShippingPage`, `RateModal`, `ConditionsEditor`, `CsvImportModal` |
| `Fraud/` | `FraudPage`, `BlockListCard`, `BlockEntryModal`, `LimitsCard`, `MaxQuantityCard`, `OtpModeCard`, `RtoGatingCard`, `BlockedAttemptsTable`, `reasons.js` |
| `Offers/` | `OffersPage`, `OffersListPage`, `OfferEditorShell`, `QuantityOfferEditor`, `BumpEditor`, `UpsellEditor`, `DownsellEditor`, `ThresholdEditor`, `AbTestsPage`, `AbTestEditor`, `OfferTargetingCard`, `DiscountFields`, `VariantField`, `offerMeta.js` |
| `Analytics/` | `CodFormAnalytics`, `FunnelChart`, `BreakdownTable`, `Filters` |
| `Integrations/` | `FormPixelsPage`, `PixelModal`, `GoogleSheetsPage`, `KlaviyoOmnisendCard`, `hubCards.jsx`, `platforms.js` |
| `Summary/` | `CodFormSummaryCard` |

Also created: this file.

## 2. Existing files touched (all edits additive; nothing reformatted)

| File | Edit |
| --- | --- |
| `Pages/SettingsHub/registry.js` | 4 names added to the icon import; group `cod-form` added as the **first** element of `SETTINGS_GROUPS`; `codFormVisible` + the six items of H.1 added at the top of `SETTINGS_ITEMS`; three paths (`/integrations/tiktok`, `/integrations/form-pixels`, `/integrations/google-sheets`) added to the `altPaths` of the existing Integrations item so the sidebar keeps it selected on the new screens. |
| `Pages/SettingsHub/icons.jsx` | Appended `ButtonIcon`, `DeliveryIcon`, `SettingsIcon`, `ShieldCheckMarkIcon` — path data copied from `@shopify/polaris-icons` 9.x, same pattern as the file. |
| `Pages/SettingsHub/SettingsHub.jsx` | One import and `codForm: useCodFormBootstrap()` added to `visibilityCtx` (and to its dependency list). |
| `Pages/Home.jsx` | Three `React.lazy` imports; three route branches before the `/features/otp…` branch (each wrapped in `React.Suspense`, because `Home` has no Suspense boundary); `/usage-analytics/cod-form` added to the analytics condition. |
| `Components/AnalyticsDashboardTabs.jsx` | Lazy `CodFormAnalytics`; "COD Form" tab appended as the last tab (index 6), only when the module is on for the shop; `case 6`. |
| `Components/Summary.jsx` | Import + `<CodFormSummaryCard />` right after `<OneClickCheckoutCard />`. |
| `Components/Integrations/IntegrationsHub.jsx` | Import; `const codFormCards = useCodFormIntegrationCards()`; the grid maps `[...integrations, ...codFormCards]`. The hook returns `[]` unless the module is on. |
| `Components/Billing.jsx` | Import + `<BillingUsageRows />` above the date-range card. |
| `Components/CODShowHide.jsx` | Import; `<FreePlanFormNote feature="limit_cod" …/>` under the existing banner; `<LimitCodPostalNotice …/>` directly after the Location rules row. |
| `Components/CODFeesSettings.jsx`, `Components/CODFeesSettingsNew.jsx` | Import + `<FreePlanFormNote feature="cod_fees" …/>`. |
| `Components/SettingWrapper.jsx` (the OTP and UI-customization screens) | Import + `<ExpressOnlyBanner variant=…/>` on the pre-order route: `express` on UI customization ("Express checkout only" → Form designer), `otp` on OTP verification ("these settings also drive the form's OTP step"). Shown only when `mode === "cod_form"`. |
| `Components/QuickOnboardingV2.jsx` | Import + `{currentStep === 2 && <OnboardingSetupStep />}` under the step content. |
| `config/localeJson/en.json` | 1,125 keys added: new top-level section `cod_form` (1,103 keys), 13 keys under `integrations` (`tiktok`, `form_pixels`, `google_sheets`, `klaviyo`, `omnisend`, `address_autocomplete`, `category_cod_form`), 7 under `settings_hub`, `analytics_tabs.cod_form`, `partial.express_order_form_toggle`. **One existing value changed:** `partial.cod_form_enabled_label` "Complete COD payment there itself" → "Express order form: complete the COD order in the popup" (the relabel of spec §12). Nothing removed. The file was rewritten with the same serialisation it already had (2-space indent, UTF-8, trailing newline). |

`Components/PartialPayment/PartialPayment.jsx` was **not** edited — see deviation 3.

Every component added to an existing screen renders nothing when `GET /cod_form/bootstrap` says the module is off, or when the call fails.

## 3. How it was verified

The app's `node_modules` are not installed in the mirror and webpack cannot run, so verification used private tooling in `/tmp/ws7-tools` (outside the repo). `/tmp/ws7-tools/run-all.sh` runs both steps.

1. **`verify.js`** — 116 files (the 103 new ones + the 13 edited JS/JSX files):
   - Babel transform with `@babel/preset-env` + `@babel/preset-react`: no syntax errors.
   - Every relative import resolves to a real file, and every named import exists as an export of its target.
   - Every named import from `@shopify/polaris` (12.6.0), `@shopify/polaris-icons` (4.5.0), `@shopify/app-bridge-react` (4.2.8), `recharts` (2.1.9) and `react` was checked against the installed package at the version `package.json` pins.
   - No undefined identifiers in the new files (scope analysis).
   - Every `t()` / `tg()` call has a literal key and fallback, passes the variables its text uses, and its key exists in `en.json` with the same English text (1,117 keys).
   - Result: `116 files checked, 1117 i18n keys, 0 errors`.
2. **`smoke/run.js`** — the whole module bundled with esbuild (real Polaris, recharts, styled-components, the app's real `i18n-lang`, `Country`, `SettingsPrimitives`, `navigate`, `registry`; stubs only for axios, the Store context and the App Bridge `SaveBar`) and rendered in jsdom against fixtures written from D.15:
   - 116 screen renders: every route of H.4, the two integration pages, the analytics tab and the components added to existing screens, each in three situations — all gates allowed, Free-plan gates, and the API answering 500 / 402 / 403 — plus the module-off and mode-off cases. Tabs are clicked through and the modals opened.
   - 11 interaction flows that edit a field, use the save bar and assert the request: `PUT /button`, `PUT /setup`, `POST /mode`, `POST` and `PUT` and `DELETE /shipping_rates`, `POST /offers` (after the client-side validation blocks an unnamed offer), `POST /offers/:id/status`, `PUT /forms/:id`, `POST /block_entries`, `PUT /fraud`, `POST /pixels`.
   - Registry checks (group first, six items hidden until the module flag is true, longest-prefix selection) and unit checks of the pure helpers (postal syntax, money, deep merge).
   - Result: 130 checks, `0 failures`, no React errors or missing translations.

Not verified: a real webpack build, a real browser, the real App Bridge (save bar, resource picker, toast), and visual appearance. See the QA steps in section 7.

After the WS6 controllers and `notes/ws6.md` appeared in the tree I read them against `api.js`; request and response shapes agree (details in section 5). The "For WS7" points of that note are applied: engine error codes are mapped to copy, `embed.enabled: null` is shown as "Not checked", the preview frame listens for `codkf:preview_ready` / `codkf:preview_error` (an error falls back to the mock), the Google popup message `codkf:google_sheets` ends the wait, a failed replace-mode CSV import says nothing was changed, and the export is fetched as a blob.

## 4. Deviations from ARCHITECTURE.md

1. **Preview renderer.** The designer's default preview is `components/FormMock.jsx`, a React mock built from the draft config (the workstream brief asked for a mock and no import of the storefront package). The H.6 iframe (`PreviewFrame.jsx`, `codkf:preview` messages, 150 ms debounce) is implemented and offered as a second renderer ("Storefront form") in the preview only when `bootstrap.preview.asset_base` is known. The buttons preview is a static mock (`ButtonPreview.jsx`).
2. **Extra files** beyond the H.4 list, all inside the owned folder: `i18n.js`, `utils.js`, `defaults.js`, `components/{Screen,FormMock,ModuleDisabled,LimitCodNotes,BillingUsageRows,OnboardingSetupStep}.jsx`, `Designer/{DesignerRoute.jsx,texts.js,formDefaults.js,fieldLabels.js}`, `Fraud/reasons.js`, `Offers/{OfferEditorShell,DiscountFields,VariantField}.jsx`, `Offers/offerMeta.js`, `Integrations/{hubCards.jsx,platforms.js}`.
3. **Express toggle relabel.** The toggle is rendered by `addPartialPaymentOptions.jsx` (not a WS7 file) with the key `partial.cod_form_enabled_label`; `PartialPayment.jsx` does not render it. The relabel is therefore done only by changing that key's English text; `partial.express_order_form_toggle` is added as the short label. No JSX was changed.
4. **Postal help text.** The two postal fields are rendered by `CODShowHide/codkiLocationRules.jsx` (not a WS7 file). The help text and the two allow-list banners (exact product copy) are shown in one block directly under the Location rules row, when the postal option is ticked.
5. **Extra route** `/features/cod-form/designer/forms` (always the forms list), so a shop with one form can reach the list to add a second. It is covered by the `(/*section)` page route.
6. **Klaviyo, Omnisend and address autocomplete** have no page route of their own in D.16. The two CRM cards live at the bottom of `/integrations/form-pixels` (hub cards link to `#klaviyo` / `#omnisend`); the Google Maps key is in Setup → More options (hub card links to `/features/cod-form#address-autocomplete`).
7. **Hub icons** are the exact `@shopify/polaris-icons` 9 paths as H.1 says; the Integrations item's `altPaths` gained the three new paths (not written in H.1) so the sidebar highlight is right.
8. **i18n variables** in admin strings use the i18n-js form `%{count}` (the product copy is written `{count}`); buyer-text variables such as `{total}` are left as single braces.
9. **Country list.** `Components/Country.jsx` has six rows whose `value` is a name fragment instead of an ISO code (`'Republic of'` for Korea and Moldova, `'State of'` for Palestine, …). `constants.js` drops those rows and adds BQ, CD, KR, MD, PS, SH back, because this module stores ISO-2 codes. `Country.jsx` itself is not edited.
10. **`template_key` on form update** is not sent (D.15 lists `name`, `targeting`, `draft_config`). Applying a template changes `design` and block order in the draft; the form's `template_key` column keeps its creation value.

## 5. What WS6 must match (checked against the controllers in the tree on 3 Oct)

- `GET /cod_form/bootstrap` must answer 200 for every shop, with `module_enabled: false` when the module is off (it is called from the Settings hub, Summary, Analytics tabs, Integrations, Billing, Limit COD, COD fees, OTP and onboarding screens). A 4xx/5xx is treated as "module off".
- `GET /cod_form/offers?type=` is called with the singular DB values `quantity | bump | upsell | downsell | threshold`. `GET /cod_form/offers/:id` and `GET /cod_form/ab_tests/:id` are used by the editors.
- Bodies are sent unwrapped: a shipping rate is the C.3 object without `id`; an offer is the C.4 wrapper without `id` and `ab_test_id`; a pixel is C.6 without `id` and `access_token_masked`, with `access_token` only when the merchant typed one. Toggling a rate's Active box sends the whole rate with `PUT`.
- `PUT /cod_form/setup` sends the complete `general` object. `PUT /cod_form/fraud` sends `{fraud, otp, rto}`.
- `PUT /cod_form/forms/:id` → the form at the top level; `warnings` and `publish_errors` are shown when present. `has_unpublished_changes` is used when it is a boolean, otherwise the client compares draft and published config.
- Lists: `{items: [...]}`; paged lists `meta: {page, pages, count}` (`block_entries`, `rejections`).
- `conversion_rate` is a number 0–100. `health[].action_url` starting with `/` is opened inside the app, anything else in a new tab.
- `GET /cod_form/analytics/export.csv` is fetched with the session token as a blob.
- `integrations` items: `status` `connected | error | disconnected`; `available: false` on `google_sheets` shows "not available"; `auth_url` answering 404 or `not_available` does the same.

## 6. Open issues

1. **Landing page of Settings.** `/settings-hub` selects the first visible item. The COD Form group is hidden until bootstrap resolves, so the first visit of a page load still lands on OTP verification; later visits land on COD Form Setup. Decide which is wanted.
2. **Opt-in card cannot be dismissed.** `setup_state.dismissed_optin_at` exists but no endpoint writes it; the Summary card stays until the form is turned on.
3. **Product and collection names.** Only ids are stored. Tags show the title when it was picked in this browser session (cached in `sessionStorage`), otherwise `#<id>`. A lookup endpoint would fix it.
4. **Pre-existing data bug** in `Components/Country.jsx` (deviation 9) — affects the existing Limit COD country selector too; needs its owner.
5. **Preview country field.** The mock hides the country field (it does not know how many countries Setup enables).
6. **Other locales.** Only `en.json` was edited; the new keys reach the other locale files through Crowdin. Until then every string falls back to the English text in code.
7. `config/crowdin.yml` and `crowdin.yml` contain Crowdin API tokens in plain text. Not touched; worth rotating.

## 7. Manual QA (needs a dev store with WS1–WS6 merged and the page routes of `ws6-routes.md` in `config/routes.rb`)

1. Shop **without** the module: Settings has no COD Form group; Summary, Integrations, Billing, Analytics, Limit COD, COD fees, OTP and onboarding look exactly as before; `/features/cod-form` shows "not available".
2. Turn the module on for the shop (internal admin → shop config → `module_access: on`), reload: group "COD Form" is first in the Settings sidebar with six items; search finds "upsell", "fake orders", "buy button".
3. **Setup:** Turn on → confirmation → mode badge "On"; embed card shows Off, "Open theme editor" opens a new tab on the `cod-form-embed` block; after enabling, "Check again" turns it On. Change countries / pages / products / order total → save bar → Save → reload keeps values; Discard restores. Health shows the legacy-embed banner with the exact copy when the old embed is on. Create a test link, place a test order, check the checklist ticks.
4. **Buttons:** switch B / C / A, change label (with `{total}`), colours, radius, shadow, icon, animation, placement; the preview follows; rename is disabled in B; save and check the storefront.
5. **Form designer:** hide / require / reorder fields (drag on desktop, arrows on mobile), edit label / placeholder / error per language, add a custom dropdown field, add a trust-badges block, reorder blocks (Submit stays last), change colours (contrast warning), apply a template, switch language and edit texts, set each thank-you type. Save draft → storefront unchanged; Publish → storefront changed; Discard draft restores the published version. Mobile and desktop preview, OTP and thank-you views, an RTL language.
6. **Forms list** (Pro): New form → targeting → publish; Duplicate; Make default; Archive. On Free the second form shows the upgrade card.
7. **Shipping rates:** empty state → add a rate, a free rate with a minimum subtotal, a province rate (`HU-BU`); reorder; toggle active; delete; import the sample CSV with one broken row and check the row error list; replace mode.
8. **Fraud:** add a phone, a `*@domain.com` email and a CIDR range; bulk paste with invalid lines; search; delete; turn on a phone limit; set maximum quantity; switch OTP mode (risk-based locked on Free); blocked attempts list and its reason filter.
9. **Offers:** directory cards and lock badges per plan; quantity offer with 5 tiers (6th blocked), duplicate quantity and overlap with another active offer rejected; bump (custom and product); upsell; one active downsell only; threshold (Pro); A/B test: weights must total 100, start locks the editor, results table, stop.
10. **Analytics → COD Form tab:** funnel, KPIs, date presets, country / device / product filters, compare, breakdowns and CSV export (Pro), upgrade card on Free.
11. **Integrations:** new cards appear; add a TikTok pixel with token and send a test event; second pixel of a platform; Snapchat / Pinterest; Google Sheets connect popup, pick sheet, reorder columns, save, disconnect; Klaviyo / Omnisend keys (Pro).
12. **Existing screens with COD Form on:** UI customization shows the Express-only banner; OTP verification shows the note; Limit COD shows the postal help, the warning with a prefix in the allow list and the critical banner with no exact code; COD fees and Limit COD show the Free-plan note on Free; Billing shows form order usage (and the overage line once a rate is set); Summary shows the usage meter, and the 80 % / 100 % / flagged notices at those volumes; partial payment rule editor shows the new toggle label.
13. Unsaved changes: with the save bar open, in-app navigation is blocked (same as other screens); a 402 from any save shows the upgrade card, a 422 lists the messages.
14. Mobile width (below 768 px): every screen stacks to one column, the hub drawer works, tables scroll.
