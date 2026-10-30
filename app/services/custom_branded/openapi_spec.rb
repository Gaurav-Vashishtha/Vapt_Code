# frozen_string_literal: true

module CustomBranded
  # OpenAPI 3.0 spec for the ParcelX WhatsApp Automation API, rendered by
  # Swagger UI on the ops panel's docs tab (/cb-stats?tab=docs). Built per
  # request so `servers` carries the real base URL (prod / tunnel / local).
  module OpenapiSpec
    module_function

    def build(base_url)
      {
        openapi: '3.0.3',
        info: {
          title: 'ParcelX WhatsApp Automation API',
          version: 'v1',
          description: <<~MD
            One access token (the partner API key) authorizes every call; the brand is selected per request with `shop_domain` (JSON body on POST/PATCH, query param on GET/DELETE). Click **Authorize** and paste the token to use *Try it out* — every executed request shows a copyable cURL.

            **Typical flows**
            1. **Onboard a merchant** — `POST /brands` → redirect the merchant's browser to `connect_url` → they link their WhatsApp number → poll `GET /accounts` until `ready_to_send: true`.
            2. **Set up messaging** — `POST /templates` (or `POST /templates/sync` for WhatsApp-Manager-made ones) → wait for `approved` via webhook or re-list.
            3. **Send updates** — `POST /messages` → track via webhooks or `GET /messages/{id}`.
            4. **Handle replies** — inbound messages arrive on your webhook with `context.id` linking to the message replied to.
            5. **Monitor** — `GET /messages?status=failed`, `GET /brands`, and this panel.

            Webhooks (events **we** push to **your** server) are documented below the API explorer.
          MD
        },
        servers: [{ url: base_url }],
        security: [{ bearerAuth: [] }],
        tags: [
          { name: 'Brands', description: 'Register and query brands (partner token only)' },
          { name: 'Numbers', description: "A brand's WhatsApp numbers — multiple allowed, one default. Connecting itself happens in a browser (Meta embedded signup)." },
          { name: 'Templates', description: 'Meta-reviewed message templates on a brand\'s WABA' },
          { name: 'Events', description: 'ParcelX shipment events and the templates merchants mapped to them' },
          { name: 'Messages', description: 'Send template messages, check status, browse history' },
          { name: 'API keys', description: 'Optional brand-scoped keys (partner token only)' },
          { name: 'Webhook testing', description: 'Fire signed sample webhooks at your configured URL to verify the integration' }
        ],
        paths: paths,
        components: components
      }
    end

    def paths
      {
        '/api/v1/cb/brands' => {
          post: {
            tags: ['Brands'], summary: 'Register a brand (idempotent) and get signed URLs',
            description: 'Returns signed `connect_url` (merchant page: connect a number, nothing else) and `portal_url` (brand page: numbers + templates). Your server just 302-redirects the merchant — no HMAC work on your side. Links last 7 days; call again for fresh ones.',
            requestBody: json_body(
              { shop_domain: 'merchantstore.com', label: 'Merchant Store' },
              required: %w[shop_domain]
            ),
            responses: {
              '201' => json_response('Brand registered', BRAND.merge(
                connect_url: 'https://<host>/cb/merchantstore.com/connect?exp=1789...&sig=9f2c...',
                portal_url: 'https://<host>/cb/merchantstore.com?exp=1789...&sig=9f2c...',
                links_expire_at: '2026-09-09T12:00:00Z'
              )),
              '422' => error_response('invalid domain "bad domain!"')
            }
          },
          get: {
            tags: ['Brands'], summary: 'List all brands, or query one',
            parameters: [shop_domain_param(required: false, desc: 'Return just this brand')],
            responses: { '200' => json_response('Brands with connection + usage summary', { brands: [BRAND_FULL] }) }
          }
        },

        '/api/v1/cb/accounts' => {
          get: {
            tags: ['Numbers'], summary: "List a brand's connected numbers",
            description: 'A number must show `ready_to_send: true` before sends succeed.',
            parameters: [shop_domain_param],
            responses: { '200' => json_response('Connected numbers', { shop_domain: 'merchantstore.com', accounts: [ACCOUNT, ACCOUNT_2] }) }
          }
        },
        '/api/v1/cb/accounts/{account_id}' => {
          patch: {
            tags: ['Numbers'], summary: 'Rename a number or make it the default sender',
            parameters: [id_param('account_id', 15)],
            requestBody: json_body({ shop_domain: 'merchantstore.com', label: 'Marketing line', is_default: true }, required: %w[shop_domain]),
            responses: { '200' => json_response('Updated number', ACCOUNT_2.merge(label: 'Marketing line', is_default: true)), '404' => error_response('account not found') }
          },
          delete: {
            tags: ['Numbers'], summary: 'Disconnect a number',
            description: 'Removes the number and its message logs; another number (if any) is promoted to default.',
            parameters: [id_param('account_id', 15), shop_domain_param],
            responses: { '200' => json_response('Disconnected', { ok: true, numbers_remaining: 1 }), '404' => error_response('account not found') }
          }
        },

        '/api/v1/cb/templates' => {
          get: {
            tags: ['Templates'], summary: "List a brand's templates",
            description: 'Local mirror kept fresh by Meta webhooks and sync. Send only templates with `approved: true`. `status`: pending → approved | rejected | paused | disabled.',
            parameters: [shop_domain_param],
            responses: { '200' => json_response('Templates', { templates: [TEMPLATE] }) }
          },
          post: {
            tags: ['Templates'], summary: 'Create a template (submitted to Meta for review)',
            description: <<~MD,
              `components` use Meta's own shape. Rules:
              - **BODY** (required, ≤1024 chars): variables `{{1}}…{{n}}`; `example.body_text` is **required** when variables exist.
              - **HEADER** (optional): `format: TEXT` (≤60 chars) or `IMAGE`/`VIDEO`/`DOCUMENT` with `example.header_handle: [<https sample url>]` — then also pass top-level `header_media` so sends have a default file.
              - **FOOTER** (optional, ≤60 chars, static).
              - **BUTTONS** (≤3): `QUICK_REPLY` (`text` ≤25) and/or `URL`; a `{{n}}` suffix in `url` makes it dynamic and **requires** its `example` array.

              Returns 201 with `status: "pending"` until Meta approves. Optional `account_id` targets a specific number.
            MD
            requestBody: json_body(TEMPLATE_CREATE, required: %w[shop_domain name language category components]),
            responses: { '201' => json_response('Created (pending review)', { template: TEMPLATE.merge(status: 'pending', approved: false) }), '422' => error_response('(#100) Message template name already exists') }
          }
        },
        '/api/v1/cb/templates/{template_id}' => {
          patch: {
            tags: ['Templates'], summary: "Edit a template's content on Meta",
            description: 'The template returns to `pending` for re-review. Only approved / rejected / paused templates can be edited.',
            parameters: [id_param('template_id', 205)],
            requestBody: json_body({ shop_domain: 'merchantstore.com', components: [{ type: 'BODY', text: 'Hi {{1}}, order {{2}} is on its way!', example: { body_text: [['Ravi', '#1042']] } }] }, required: %w[shop_domain components]),
            responses: { '200' => json_response('Updated (pending re-review)', { template: TEMPLATE.merge(status: 'pending', approved: false) }), '404' => error_response('template not found') }
          },
          delete: {
            tags: ['Templates'], summary: 'Delete a template (on Meta and here)',
            parameters: [id_param('template_id', 205), shop_domain_param],
            responses: { '200' => json_response('Deleted', { ok: true }), '404' => error_response('template not found') }
          }
        },
        '/api/v1/cb/templates/sync' => {
          post: {
            tags: ['Templates'], summary: "Pull the WABA's templates + review statuses from Meta",
            description: 'Use after creating templates directly in WhatsApp Manager.',
            requestBody: json_body({ shop_domain: 'merchantstore.com' }, required: %w[shop_domain]),
            responses: { '200' => json_response('Synced templates', { templates: [TEMPLATE] }) }
          }
        },

        '/api/v1/cb/events' => {
          get: {
            tags: ['Events'], summary: 'Event catalog and the variables each event allows',
            description: 'Mirrors the ParcelX registered-event API (cached for an hour; `refresh=1` re-pulls). Every leaf of an event payload becomes a variable keyed by its dot path; arrays are exposed through their first element (`order_details.product.0.name`).',
            parameters: [shop_domain_param, { name: 'refresh', in: 'query', required: false, schema: { type: 'boolean' } }],
            responses: { '200' => json_response('Events', { events: [EVENT] }), '502' => error_response('events_unavailable') }
          }
        },
        '/api/v1/cb/event_templates' => {
          get: {
            tags: ['Events'], summary: 'Templates mapped to events, with the variables each one needs',
            description: 'Merchants map templates to events on the portal. A brand can keep several templates per event but only one is `active`. `required_variables` is exactly what `POST /messages` needs in `variables` for that template.',
            parameters: [
              shop_domain_param,
              { name: 'event_id', in: 'query', required: false, schema: { type: 'string' } },
              { name: 'active', in: 'query', required: false, schema: { type: 'boolean' }, description: 'Only the active template per event' }
            ],
            responses: { '200' => json_response('Mappings', { event_templates: [EVENT_TEMPLATE] }) }
          }
        },

        '/api/v1/cb/messages' => {
          post: {
            tags: ['Messages'], summary: 'Send a template message',
            description: <<~MD,
              Include **only what the template declares**:
              - `variables` — body `{{n}}` values (map keyed by number, or an array). For a template mapped to a ParcelX event, send them **by name** instead: the keys listed in that template's `required_variables` (e.g. `consignee_details.name`). Passing the whole event payload as `variables` also works — values are read by path. Named values also fill mapped dynamic URL buttons.
              - `event_id` — instead of `template_id`: sends the brand's **active** template for that event (422 `no_active_template_for_event` when none).
              - `header_text` — only for a TEXT header containing `{{n}}`.
              - `header_image_url` / `header_video_url` / `header_document_url` — only for media headers (overrides the template's default `header_media`).
              - `button_param` — fills **every** dynamic URL button's `{{n}}`; or `button_params` per button index (wins).
              - Quick-reply buttons need nothing — payloads are auto-filled with the button text.

              `idempotency_key` makes retries safe: a repeat returns the original with `duplicate: true`. Everything is validated **before** queueing — failures come back as 422 with a machine-readable `error`.
            MD
            requestBody: {
              required: true,
              content: { 'application/json' => { examples: {
                'Event-mapped template (named variables)' => { value: { shop_domain: 'merchantstore.com', template_id: 207, to: '919876501234', variables: { 'consignee_details.name' => 'Rahul Sharma', 'consignee_details.city' => 'New Delhi' }, idempotency_key: '100000-3' } },
                'By event (active template)' => { value: { shop_domain: 'merchantstore.com', event_id: '3', to: '919876501234', variables: { 'consignee_details.name' => 'Rahul Sharma', 'consignee_details.city' => 'New Delhi' }, idempotency_key: '100000-3' } },
                'Text-only template' => { value: { shop_domain: 'merchantstore.com', template_id: 205, to: '919876543210', variables: { '1' => 'Ravi', '2' => '#1042' }, idempotency_key: 'order-1042-shipped' } },
                'Image header + dynamic URL buttons' => { value: { shop_domain: 'merchantstore.com', template_name: 'sale_banner', language: 'en', to: '919876543210', variables: { '1' => 'Ravi' }, header_image_url: 'https://cdn.merchantstore.com/banner.jpg', button_params: { '0' => 'summer-sale', '1' => 'coupon-XY12' } } },
                'Text header with variable' => { value: { shop_domain: 'merchantstore.com', template_id: 208, to: '919876543210', variables: { '1' => '#1042' }, header_text: 'Ravi' } }
              }, schema: { type: 'object' } } }
            },
            responses: {
              '202' => json_response('Queued', { status: 'queued', shop_domain: 'merchantstore.com', template: 'order_shipped', to: '919876543210', idempotency_key: 'order-1042-shipped' }),
              '422' => {
                description: 'Validation failed — machine-readable `error`, human `detail`',
                content: { 'application/json' => { examples: {
                  'template not approved' => { value: { error: 'template_not_approved', detail: 'Template status is pending.' } },
                  'number not ready' => { value: { error: 'account_not_registered', detail: 'The WhatsApp number is not ready to send. Check registration on the portal.' } },
                  'missing button param' => { value: { error: 'button_param_required', detail: 'This template has 2 URL button(s) with a dynamic {{n}} placeholder (at index 0, 1) — pass button_param (applied to all) or button_params (per index).' } },
                  'missing variables' => { value: { error: 'template expects 2 variable(s), got 1' } },
                  'missing named variables' => { value: { error: 'missing_variables', detail: 'Template 207 is mapped to event 3 (Out for Delivery) and needs: consignee_details.name, consignee_details.city. Missing or empty: consignee_details.city.' } },
                  'no active template' => { value: { error: 'no_active_template_for_event', detail: 'No active template is mapped to event 3 for this brand.' } },
                  'missing header' => { value: { error: 'template has a IMAGE header — pass header_image_url' } }
                } } }
              }
            }
          },
          get: {
            tags: ['Messages'], summary: 'Message history (newest first)',
            parameters: [
              shop_domain_param,
              { name: 'status', in: 'query', required: false, schema: { type: 'string', enum: %w[queued sent delivered read failed] } },
              { name: 'to', in: 'query', required: false, schema: { type: 'string' }, description: 'Recipient digits' },
              { name: 'template_id', in: 'query', required: false, schema: { type: 'integer' } },
              { name: 'limit', in: 'query', required: false, schema: { type: 'integer', default: 25, maximum: 100 } },
              { name: 'before_id', in: 'query', required: false, schema: { type: 'integer' }, description: 'Cursor: pass the previous page\'s next_before_id' }
            ],
            responses: { '200' => json_response('History page', { messages: [MESSAGE.merge(status: 'failed', error_code: '131008', error_message: '(#131008) Required parameter is missing — buttons: Button at index 1 of type Url requires a parameter', delivered_at: nil)], next_before_id: 431 }) }
          }
        },
        '/api/v1/cb/messages/{id}' => {
          get: {
            tags: ['Messages'], summary: 'Message status by id or idempotency key',
            description: 'Statuses progress `queued → sent → delivered → read`; `failed` is terminal with Meta\'s error.',
            parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' }, example: 'order-1042-shipped', description: 'Numeric message_id OR your idempotency_key' }, shop_domain_param],
            responses: { '200' => json_response('Message', MESSAGE), '404' => error_response('message not found') }
          }
        },

        '/api/v1/cb/keys' => {
          get: {
            tags: ['API keys'], summary: "List a brand's keys",
            parameters: [shop_domain_param],
            responses: { '200' => json_response('Keys (masked)', { shop_domain: 'merchantstore.com', keys: [KEY] }) }
          },
          post: {
            tags: ['API keys'], summary: 'Mint a brand-scoped key',
            description: 'The raw `key` appears **once**, only in this response.',
            requestBody: json_body({ shop_domain: 'merchantstore.com', label: 'merchant-erp' }, required: %w[shop_domain]),
            responses: { '201' => json_response('Minted — copy `key` now', KEY.merge(key: 'cbk_1f7b9c4d0a…48-hex…')) }
          }
        },
        '/api/v1/cb/webhook_tests' => {
          post: {
            tags: ['Webhook testing'], summary: 'Send a sample webhook to your configured URL',
            description: 'Fires a Meta-shaped sample at the configured forward URL, signed exactly like a real delivery, and returns your endpoint\'s actual response. The sample carries an `X-CB-Test: true` header and `wamid.TEST…` ids, and is recorded in the delivery log with `fields: "test:<event>"`. Uses the brand\'s real WABA / phone-number ids when a number is connected.',
            requestBody: json_body({ shop_domain: 'merchantstore.com', event: 'delivery_status' }, required: %w[shop_domain event]),
            responses: {
              '200' => {
                description: 'Result of the delivery attempt (delivered may be false)',
                content: { 'application/json' => { examples: {
                  'delivered' => { value: { delivered: true, response_code: 200, response_body: 'ok', forward_url: 'https://partner.example.com/webhooks/whatsapp', signed: true, payload: { object: 'whatsapp_business_account', entry: ['…sample entry…'] } } },
                  'endpoint down' => { value: { delivered: false, response_code: nil, error: 'Net::OpenTimeout', forward_url: 'https://partner.example.com/webhooks/whatsapp', signed: true, payload: { object: 'whatsapp_business_account', entry: ['…sample entry…'] } } }
                } } }
              },
              '422' => error_response('unknown event "bogus" — use one of: delivery_status, inbound_reply, template_review')
            }
          }
        },
        '/api/v1/cb/keys/{key_id}' => {
          delete: {
            tags: ['API keys'], summary: 'Revoke a key (immediate)',
            parameters: [id_param('key_id', 7), shop_domain_param],
            responses: { '200' => json_response('Revoked', { ok: true }), '404' => error_response('key not found') }
          }
        }
      }
    end

    def components
      {
        securitySchemes: {
          bearerAuth: {
            type: 'http', scheme: 'bearer',
            description: 'The partner API key (works on every brand — pass shop_domain per request), or a brand-scoped cbk_ key.'
          }
        }
      }
    end

    # ---- example payloads -------------------------------------------------

    BRAND = {
      shop_domain: 'merchantstore.com', label: 'Merchant Store',
      numbers_connected: 0, numbers_ready: 0,
      templates_total: 0, templates_approved: 0, messages_total: 0,
      created_at: '2026-09-02T12:00:00Z', last_portal_access_at: nil
    }.freeze

    BRAND_FULL = BRAND.merge(
      numbers_connected: 2, numbers_ready: 2, templates_total: 14,
      templates_approved: 11, messages_total: 5231,
      last_portal_access_at: '2026-09-01T18:40:11Z'
    ).freeze

    ACCOUNT = {
      account_id: 12, label: 'Support line', is_default: true, status: 'verified',
      ready_to_send: true, display_phone_number: '+91 98765 43210',
      verified_name: 'Merchant Store', quality_rating: 'GREEN',
      registration_state: 'registered', needs_registration: false,
      connected_at: '2026-08-01T10:00:00Z'
    }.freeze

    ACCOUNT_2 = ACCOUNT.merge(account_id: 15, label: nil, is_default: false).freeze

    TEMPLATE = {
      template_id: 205, name: 'order_shipped', language: 'en', category: 'UTILITY',
      status: 'approved', approved: true,
      body: 'Hi {{1}}, your order {{2}} has shipped!',
      header_format: 'TEXT', variable_count: 2,
      components: [
        { type: 'HEADER', format: 'TEXT', text: 'Order update' },
        { type: 'BODY', text: 'Hi {{1}}, your order {{2}} has shipped!', example: { body_text: [%w[Ravi #1042]] } },
        { type: 'FOOTER', text: 'Reply STOP to opt out' },
        { type: 'BUTTONS', buttons: [
          { type: 'URL', text: 'Track order', url: 'https://merchantstore.com/track/{{1}}', example: ['https://merchantstore.com/track/abc123'] },
          { type: 'QUICK_REPLY', text: 'Need help' }
        ] }
      ],
      account_id: 12, account_phone: '+91 98765 43210',
      rejection_reason: nil, event: nil, updated_at: '2026-09-02T11:30:00Z'
    }.freeze

    EVENT = {
      event_id: '3', event_name: 'Out for Delivery',
      group: 'order_updates_events', group_label: 'Order updates',
      variables: [
        { key: 'consignee_details.name', label: 'Customer name', section: 'Customer', sample: 'Rahul Sharma' },
        { key: 'consignee_details.city', label: 'City', section: 'Customer', sample: 'New Delhi' },
        { key: 'channel_details.order_id', label: 'Order ID', section: 'Sales channel', sample: 'SHOP-ORD-5001' }
      ]
    }.freeze

    EVENT_TEMPLATE = {
      template_id: 207, template_name: 'out_for_delivery', language: 'en',
      status: 'approved', approved: true, account_id: 12,
      event_id: '3', event_name: 'Out for Delivery', event_group: 'order_updates_events',
      active: true, live: true,
      variables: [
        { position: 1, key: 'consignee_details.name', label: 'Customer name', sample: 'Rahul Sharma' },
        { position: 2, key: 'consignee_details.city', label: 'City', sample: 'New Delhi' }
      ],
      button_variables: {},
      required_variables: %w[consignee_details.name consignee_details.city]
    }.freeze

    TEMPLATE_CREATE = {
      shop_domain: 'merchantstore.com',
      name: 'order_shipped', language: 'en', category: 'UTILITY',
      components: TEMPLATE[:components]
    }.freeze

    MESSAGE = {
      message_id: 456, status: 'delivered', template: 'order_shipped',
      recipient: '919876543210', meta_message_id: 'wamid.HBgMOTE5ODc2NTQzMjEwFQIAERgS…',
      error_code: nil, error_message: nil,
      sent_at: '2026-09-02T12:00:01Z', delivered_at: '2026-09-02T12:00:04Z',
      read_at: nil, failed_at: nil, created_at: '2026-09-02T12:00:00Z'
    }.freeze

    KEY = {
      key_id: 7, label: 'merchant-erp', masked: 'cbk_…5e9062',
      revoked: false, created_at: '2026-09-02T12:00:00Z', last_used_at: nil
    }.freeze

    # ---- helpers ----------------------------------------------------------

    def shop_domain_param(required: true, desc: 'Brand to operate on (required with the partner token)')
      { name: 'shop_domain', in: 'query', required: required,
        schema: { type: 'string' }, example: 'merchantstore.com', description: desc }
    end

    def id_param(name, example)
      { name: name, in: 'path', required: true, schema: { type: 'integer' }, example: example }
    end

    def json_body(example, required: [])
      {
        required: true,
        content: { 'application/json' => {
          schema: { type: 'object', required: required },
          example: example
        } }
      }
    end

    def json_response(description, example)
      { description: description, content: { 'application/json' => { example: example } } }
    end

    def error_response(message)
      { description: 'Error', content: { 'application/json' => { example: { error: message } } } }
    end
  end
end
