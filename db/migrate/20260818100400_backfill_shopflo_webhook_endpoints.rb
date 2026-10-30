# frozen_string_literal: true

class BackfillShopfloWebhookEndpoints < ActiveRecord::Migration[7.2]
  # Trigger events ship disabled so a seeded endpoint collects real payloads
  # without sending anything. Suppression events are safe on from the start
  # because they can only ever prevent a message.
  SEED_EVENT_CONFIG = {
    'checkout_abandoned'  => { 'enabled' => false, 'amount_scale' => 1.0 },
    'added_to_cart_ui'    => { 'enabled' => false, 'amount_scale' => 0.01 },
    'product_page_viewed' => { 'enabled' => false, 'amount_scale' => 1.0 },
    'checkout_clicked'    => { 'enabled' => true },
    'order_completed'     => { 'enabled' => true }
  }.freeze

  # Goes through the model rather than raw SQL because `secret` is encrypted at
  # the model layer; a raw INSERT would store plaintext the app can't decrypt.
  def up
    unless defined?(WebhookEndpoint)
      say 'WebhookEndpoint model not loaded — skipping backfill'
      return
    end

    created = 0
    skipped = 0

    eligible_shop_ids.each_slice(500) do |batch|
      Shop.where(id: batch).find_each do |shop|
        if WebhookEndpoint.exists?(shop_id: shop.id, provider: 'shopflo')
          skipped += 1
          next
        end

        WebhookEndpoint.create!(
          shop: shop,
          provider: 'shopflo',
          enabled: true,
          signature_scheme: 'shared_secret',
          signature_header: 'X-Webhook-Signature',
          event_config: SEED_EVENT_CONFIG.deep_dup,
          mirror_to_slack: false
        )
        created += 1
      rescue StandardError => e
        skipped += 1
        say "shop=#{shop.id} skipped: #{e.class}: #{e.message}"
      end
    end

    say "Shopflo webhook endpoints — created: #{created}, skipped: #{skipped}"
  end

  def down
    return unless defined?(WebhookEndpoint)

    # Endpoints that took traffic are left alone: a merchant has already wired
    # that URL into Shopflo and deleting it would silently break them.
    removed = WebhookEndpoint.where(provider: 'shopflo', last_received_at: nil).delete_all
    say "Removed #{removed} unused Shopflo webhook endpoints"
  end

  private

  def eligible_shop_ids
    legacy = Setting.where(abandoned_cart_enabled: true)
                    .or(Setting.where(ac_whatsapp: true))
                    .pluck(:shop_id)

    bsp = WhatsappTemplateBinding.where(event_type_key: 'abandoned_cart').pluck(:shop_id)

    (legacy + bsp).compact.uniq
  end
end
