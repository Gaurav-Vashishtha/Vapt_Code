# frozen_string_literal: true

class WhatsappAiSetting < ApplicationRecord
  belongs_to :shop

  SKILLS = %w[order_status cod_confirmation product_help store_faq pay_online discounts place_orders].freeze
  DEFAULT_SKILLS = SKILLS.index_with { |key| key != 'discounts' }.freeze
  TONES = %w[friendly professional].freeze
  MAX_TEST_NUMBERS = 5
  MAX_KNOWLEDGE = 8000
  MAX_HANDOFF_TEXT = 500
  MAX_AGENT_NAME = 40
  DEFAULT_DISCOUNT = { 'max_percent' => 10, 'min_cart_value' => 0, 'expiry_hours' => 24 }.freeze
  MAX_DISCOUNT_PERCENT = 50
  TEAM_TIMEOUTS = [0, 15, 30, 60, 120].freeze
  DAILY_REPLY_LIMITS = [0, 20, 40, 100].freeze
  DEFAULT_HANDOFF_TEXT = "Thanks! I've passed this to our team. They'll reply here shortly."
  DEFAULT_KNOWLEDGE = <<~TEXT.strip
    About us:

    Shipping (delivery time, charges, courier):

    Cash on delivery (COD charges, limits):

    Returns, exchanges and refunds:

    Contact and working hours:
  TEXT

  enum :status, { off: 0, test: 1, live: 2 }, prefix: :agent
  enum :reply_mode, { auto: 0, draft: 1 }, prefix: :reply

  validates :tone, inclusion: { in: TONES }
  validates :team_timeout_minutes, inclusion: { in: TEAM_TIMEOUTS }
  validates :daily_reply_limit, inclusion: { in: DAILY_REPLY_LIMITS }
  validates :knowledge, length: { maximum: MAX_KNOWLEDGE }
  validates :handoff_text, length: { maximum: MAX_HANDOFF_TEXT }
  validates :agent_name, length: { maximum: MAX_AGENT_NAME }
  validate :validate_test_numbers
  validate :validate_discount

  def self.for(shop)
    find_or_create_by!(shop_id: shop.id) do |s|
      s.skills = DEFAULT_SKILLS
      s.discount = DEFAULT_DISCOUNT
      s.knowledge = DEFAULT_KNOWLEDGE
      s.handoff_text = DEFAULT_HANDOFF_TEXT
    end
  rescue ActiveRecord::RecordNotUnique
    find_by!(shop_id: shop.id)
  end

  def self.normalize_number(raw)
    raw.to_s.gsub(/\D/, '')
  end

  def skill?(key)
    value = skills.is_a?(Hash) ? skills[key.to_s] : nil
    value.nil? ? DEFAULT_SKILLS.fetch(key.to_s, false) : value == true
  end

  def enabled_skills
    SKILLS.select { |key| skill?(key) }
  end

  def discount_config
    DEFAULT_DISCOUNT.merge(discount.is_a?(Hash) ? discount.slice(*DEFAULT_DISCOUNT.keys) : {})
  end

  def active?
    !agent_off?
  end

  def test_number?(phone)
    last10 = self.class.normalize_number(phone).last(10)
    return false if last10.length < 8

    Array(test_numbers).any? { |n| self.class.normalize_number(n).last(10) == last10 }
  end

  def handles?(conversation)
    return false if agent_off?
    return true if agent_live?

    test_number?(conversation.customer_wa_id)
  end

  def display_name(store_name)
    agent_name.to_s.strip.presence || "#{store_name.to_s.strip.presence || 'Store'} Assistant"
  end

  def handoff_message
    handoff_text.to_s.strip.presence || DEFAULT_HANDOFF_TEXT
  end

  def apply_api_attributes(attrs)
    attrs = attrs.is_a?(Hash) ? attrs.to_h.deep_stringify_keys : {}
    self.status = attrs['status'] if attrs.key?('status') && self.class.statuses.key?(attrs['status'].to_s)
    self.reply_mode = attrs['reply_mode'] if attrs.key?('reply_mode') && self.class.reply_modes.key?(attrs['reply_mode'].to_s)
    self.agent_name = attrs['agent_name'].to_s.strip.presence if attrs.key?('agent_name')
    self.tone = attrs['tone'].to_s if attrs.key?('tone')
    self.knowledge = attrs['knowledge'].to_s.strip if attrs.key?('knowledge')
    self.handoff_text = attrs['handoff_text'].to_s.strip if attrs.key?('handoff_text')
    self.allow_cancel = bool(attrs['allow_cancel']) if attrs.key?('allow_cancel')
    self.team_timeout_minutes = attrs['team_timeout_minutes'].to_i if attrs.key?('team_timeout_minutes')
    self.daily_reply_limit = attrs['daily_reply_limit'].to_i if attrs.key?('daily_reply_limit')
    if attrs['skills'].is_a?(Hash)
      self.skills = DEFAULT_SKILLS.merge(skills.is_a?(Hash) ? skills : {})
                                  .merge(attrs['skills'].slice(*SKILLS).transform_values { |v| bool(v) })
    end
    if attrs['discount'].is_a?(Hash)
      d = attrs['discount']
      self.discount = discount_config.merge(
        'max_percent' => d.key?('max_percent') ? d['max_percent'].to_f.round(1) : discount_config['max_percent'],
        'min_cart_value' => d.key?('min_cart_value') ? d['min_cart_value'].to_f.round(2) : discount_config['min_cart_value'],
        'expiry_hours' => d.key?('expiry_hours') ? d['expiry_hours'].to_i : discount_config['expiry_hours']
      )
    end
    if attrs.key?('test_numbers')
      self.test_numbers = Array(attrs['test_numbers']).map { |n| self.class.normalize_number(n) }.reject(&:blank?).uniq
    end
    self.went_live_at ||= Time.current if agent_live?
    self
  end

  def as_api_json
    {
      'status' => status,
      'reply_mode' => reply_mode,
      'agent_name' => agent_name.to_s,
      'tone' => tone,
      'skills' => SKILLS.index_with { |key| skill?(key) },
      'discount' => discount_config,
      'allow_cancel' => allow_cancel,
      'team_timeout_minutes' => team_timeout_minutes,
      'daily_reply_limit' => daily_reply_limit,
      'knowledge' => knowledge.to_s,
      'handoff_text' => handoff_message,
      'test_numbers' => Array(test_numbers),
      'limits' => {
        'max_test_numbers' => MAX_TEST_NUMBERS,
        'max_knowledge' => MAX_KNOWLEDGE,
        'max_discount_percent' => MAX_DISCOUNT_PERCENT
      }
    }
  end

  private

  def bool(value)
    ActiveModel::Type::Boolean.new.cast(value) == true
  end

  def validate_test_numbers
    numbers = Array(test_numbers)
    errors.add(:test_numbers, "can have up to #{MAX_TEST_NUMBERS} numbers") if numbers.size > MAX_TEST_NUMBERS
    return unless numbers.any? { |n| !n.to_s.match?(/\A\d{10,15}\z/) }

    errors.add(:test_numbers, 'must be full numbers with country code, e.g. 919876543210')
  end

  def validate_discount
    d = discount_config
    max = d['max_percent'].to_f
    if skill?('discounts') && (max <= 0 || max > MAX_DISCOUNT_PERCENT)
      errors.add(:discount, "maximum must be between 1% and #{MAX_DISCOUNT_PERCENT}%")
    end
    errors.add(:discount, 'minimum cart value cannot be negative') if d['min_cart_value'].to_f.negative?
    errors.add(:discount, 'expiry must be between 1 and 168 hours') unless (1..168).cover?(d['expiry_hours'].to_i)
  end
end
