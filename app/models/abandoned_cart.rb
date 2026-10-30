class AbandonedCart < ApplicationRecord
  belongs_to :shop
  after_create :update_wallet_balance

  # cod_form: abandoned COD Form sessions (anchor rows written by
  # CodForm::Abandonment::MarkAbandonedService), read by both schedulers like a webhook cart.
  WEBHOOK_SOURCES = %w[shopflo custom cod_form].freeze

  scope :from_webhooks, -> { where(source: WEBHOOK_SOURCES) }
  scope :anchors, -> { where(is_anchor: true) }
  scope :not_recovered, -> { where("lower(coalesce(notes, '')) <> 'recovered'") }

  def recovered?
    notes.to_s.casecmp('recovered').zero?
  end

  def webhook_sourced?
    WEBHOOK_SOURCES.include?(source.to_s)
  end

  private

  def update_wallet_balance
    # Anchors are ingest records, not sends. The legacy MSG91 path still debits
    # once per scheduled stage row and BSP bills through WhatsappMessageLog, so
    # debiting here too would double-charge every webhook-sourced cart.
    return if is_anchor?

    NetworkServices::FreeWalletService.new(shop, self.country_code, self.notif_type).call
  rescue StandardError => e
    # FreeWalletService indexes TwilioPricing by country_code and raises
    # NoMethodError on a blank or unlisted one. Unrescued that propagates out
    # of after_create and rolls back the insert, losing the cart over a
    # bookkeeping failure.
    Rails.logger.error(
      "[AbandonedCart] wallet debit failed cart=#{id} shop=#{shop_id} " \
      "country=#{country_code.inspect} mode=#{notif_type.inspect} #{e.class}: #{e.message}"
    )
    nil
  end
end
