# frozen_string_literal: true

require "administrate/base_dashboard"

class ShopDomainDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    shopify_domain: Field::String,
    last_seen_at: Field::DateTime,
    backfill_state: Field::Text,
    backfill_started_at: Field::DateTime,
    backfill_completed_at: Field::DateTime,
    backfill_last_attempt_at: Field::DateTime,
    backfill_next_retry_at: Field::DateTime,
    backfill_last_error: Field::Text,
    incremental_sync_cursor_at: Field::DateTime,
    last_reconciled_at: Field::DateTime,
    last_webhook_received_at: Field::DateTime,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    shopify_domain
    backfill_last_attempt_at
    backfill_next_retry_at
    backfill_started_at
    backfill_completed_at
    incremental_sync_cursor_at
    last_webhook_received_at
    last_reconciled_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    shopify_domain
    last_seen_at
    backfill_state
    backfill_started_at
    backfill_completed_at
    backfill_last_attempt_at
    backfill_next_retry_at
    backfill_last_error
    incremental_sync_cursor_at
    last_reconciled_at
    last_webhook_received_at
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    shopify_domain
    backfill_state
    backfill_started_at
    backfill_completed_at
    incremental_sync_cursor_at
    last_reconciled_at
    last_webhook_received_at
    last_seen_at
  ].freeze
end

