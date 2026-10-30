class WhatsappTemplateBinding < ApplicationRecord
  UNPAUSABLE_EVENTS = %w[pre_order_otp].freeze

  belongs_to :shop
  belongs_to :whatsapp_template
  # The number this event sends from. Optional — nil means "use the shop
  # default" (how every legacy binding behaves). When set, it must be a number
  # under the same WABA as the bound template (see validation below), so the
  # template is guaranteed to exist in the sending number's WABA.
  belongs_to :whatsapp_account, optional: true

  validates :event_type_key, presence: true
  # One binding per (shop, event, stage). Stage 0 is the default — non-staged
  # events (order_created etc.) only ever use stage 0. Staged events
  # (abandoned_cart) can have N entries: stage 0 = first reminder, 1 = second,
  # 2 = third, etc.
  validates :shop_id, uniqueness: {
    scope: %i[event_type_key stage_index],
    message: 'already has a template bound for this event at this stage'
  }
  validates :stage_index, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :offset_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  validate :template_belongs_to_shop
  validate :template_event_matches
  validate :template_is_approved
  validate :discount_config_is_well_formed
  validate :account_belongs_to_shop
  validate :account_shares_template_waba
  validate :pause_allowed

  scope :for_event, ->(key) { where(event_type_key: key) }
  scope :ordered_by_stage, -> { order(stage_index: :asc) }
  scope :active, -> { where(paused_at: nil) }
  scope :paused, -> { where.not(paused_at: nil) }

  def self.pausable?(event_type_key)
    !UNPAUSABLE_EVENTS.include?(event_type_key.to_s)
  end

  def self.set_paused!(shop, event_type_key, paused)
    raise ArgumentError, 'This notification cannot be paused' if paused && !pausable?(event_type_key)

    bindings = shop.whatsapp_template_bindings.for_event(event_type_key).to_a
    now = Time.current
    # update_columns: pausing must work even when an unrelated validation (e.g. the
    # template lost its approval) would block a full save.
    transaction do
      bindings.each do |binding|
        if paused
          binding.update_columns(paused_at: now, last_paused_at: now, updated_at: now) unless binding.paused?
        elsif binding.paused?
          binding.update_columns(paused_at: nil, resumed_at: now, updated_at: now)
        end
      end
    end
    bindings
  end

  def paused?
    paused_at.present?
  end

  private

  def pause_allowed
    return unless paused? && !self.class.pausable?(event_type_key)
    errors.add(:base, 'This notification cannot be paused')
  end

  def template_belongs_to_shop
    return unless whatsapp_template && shop_id
    return if whatsapp_template.whatsapp_account&.shop_id == shop_id
    errors.add(:whatsapp_template, 'does not belong to this shop')
  end

  def account_belongs_to_shop
    return unless whatsapp_account && shop_id
    return if whatsapp_account.shop_id == shop_id
    errors.add(:whatsapp_account, 'does not belong to this shop')
  end

  # The sending number must live under the same WABA as the bound template —
  # you cannot send a template from a number in a different WABA (Meta resolves
  # templates by name+language within the sending number's WABA).
  def account_shares_template_waba
    return unless whatsapp_account && whatsapp_template
    template_waba = whatsapp_template.whatsapp_account&.waba_id
    # Can't verify the WABA (e.g. Coexistence numbers persist without a
    # waba_id) — don't block; mirror the campaign-launch check.
    return if template_waba.blank?
    return if whatsapp_account.waba_id.to_s == template_waba.to_s
    errors.add(:whatsapp_account, 'must be a number under the same WhatsApp Business Account as the template')
  end

  def template_event_matches
    return unless whatsapp_template && event_type_key
    return if whatsapp_template.event_type_key == event_type_key
    errors.add(:whatsapp_template, 'was not designed for this event')
  end

  def template_is_approved
    return unless whatsapp_template
    return if whatsapp_template.approved?
    errors.add(:whatsapp_template, 'must be approved before binding')
  end

  # discount_config shape:
  #   { mode: 'none' }                                            (default)
  #   { mode: 'static', code: 'COMEBACK10', value: 10, kind: 'percent' }
  #   { mode: 'auto',   value: 10, kind: 'percent', upto: 200,
  #     prefix: 'AC', once_per_customer: true }
  # Anything else is rejected before save so the cron resolver doesn't have to
  # second-guess the data.
  def discount_config_is_well_formed
    return if discount_config.blank?
    unless discount_config.is_a?(Hash)
      errors.add(:discount_config, 'must be an object')
      return
    end

    mode = discount_config['mode'].to_s
    return if mode == 'none' || mode == ''

    unless %w[static auto].include?(mode)
      errors.add(:discount_config, "mode must be one of none / static / auto (got #{mode.inspect})")
      return
    end

    kind = discount_config['kind'].to_s
    unless %w[percent fixed].include?(kind)
      errors.add(:discount_config, "kind must be percent or fixed")
    end

    value = discount_config['value']
    unless value.is_a?(Numeric) && value.positive?
      errors.add(:discount_config, 'value must be a positive number')
    end

    if mode == 'static' && discount_config['code'].to_s.strip.empty?
      errors.add(:discount_config, 'code is required for static discounts')
    end
  end
end
