class WhatsappSegment < ApplicationRecord
  belongs_to :shop
  has_many :campaigns, class_name: 'WhatsappCampaign', dependent: :nullify

  FILTER_KEYS = %w[
    tags_any tags_all tags_none sources include_unsubscribed
    created_from created_to min_orders max_orders min_spent max_spent
    last_order_within_days last_order_older_than_days
    cod_only min_cod_orders rto unconfirmed_cod_within_days
  ].freeze

  RTO_MODES = %w[only exclude].freeze

  validates :name, presence: true, uniqueness: { scope: :shop_id }

  def self.sanitize_filters(raw)
    h = (raw || {}).to_h.stringify_keys.slice(*FILTER_KEYS)
    %w[tags_any tags_all tags_none].each do |k|
      h[k] = WhatsappContact.sanitize_tags(h[k]) if h.key?(k)
    end
    h['sources'] = Array(h['sources']).map(&:to_s) & WhatsappContact::SOURCES if h.key?('sources')
    h['cod_only'] = true if ActiveModel::Type::Boolean.new.cast(h['cod_only']) == true
    h.delete('cod_only') unless h['cod_only'] == true
    h.delete('rto') unless RTO_MODES.include?(h['rto'].to_s)
    h.compact_blank
  end

  def matching_scope
    Whatsapp::SegmentQuery.scope(shop_id, filters)
  end

  def refresh_count!
    update_columns(cached_count: matching_scope.count, counted_at: Time.current, updated_at: Time.current)
  rescue StandardError => e
    Rails.logger.warn("[WhatsappSegment] count failed segment=#{id} #{e.message}")
  end
end
