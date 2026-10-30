# frozen_string_literal: true

class WhatsappInboxSetting < ApplicationRecord
  belongs_to :shop

  DAYS = %w[mon tue wed thu fri sat sun].freeze
  MATCHES = %w[contains exact].freeze
  VARIABLES = %w[name first_name order_number order_status tracking_url order_amount store_name].freeze
  UNANSWERED_MINUTES = [15, 30, 60].freeze
  MAX_KEYWORD_RULES = 10
  MAX_KEYWORDS_PER_RULE = 10
  MAX_KEYWORD_LENGTH = 30
  MAX_TEXT_LENGTH = 1024
  TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/

  DEFAULT_WELCOME_TEXT = "Hi {{first_name}}, thanks for messaging {{store_name}}! We'll reply shortly."
  DEFAULT_AWAY_TEXT = "Hi {{first_name}}, we're away right now and will reply when we're back. " \
                      'For order updates: {{tracking_url}}'

  validates :welcome_text, :away_text, length: { maximum: MAX_TEXT_LENGTH }
  validates :welcome_text, presence: true, if: :welcome_enabled?
  validates :away_text, presence: true, if: :away_enabled?
  validates :unanswered_email_minutes, inclusion: { in: UNANSWERED_MINUTES }
  validate :validate_business_hours
  validate :validate_keyword_rules

  def self.for(shop)
    find_or_create_by!(shop_id: shop.id) do |s|
      s.welcome_text = DEFAULT_WELCOME_TEXT
      s.away_text = DEFAULT_AWAY_TEXT
    end
  rescue ActiveRecord::RecordNotUnique
    find_by!(shop_id: shop.id)
  end

  def self.normalize_business_hours(raw)
    hash = raw.is_a?(Hash) ? raw : {}
    return {} if hash.blank?

    DAYS.index_with do |day|
      Array(hash[day] || hash[day.to_sym]).filter_map do |range|
        pair = Array(range).map { |v| v.to_s.strip }
        pair.first(2) if pair.size >= 2
      end
    end
  end

  def self.normalize_keyword_rules(raw)
    Array(raw).map do |rule|
      rule = rule.is_a?(Hash) ? rule.to_h.stringify_keys : {}
      keywords = Array(rule['keywords']).map { |k| k.to_s.squish }.compact_blank.uniq(&:downcase)
      {
        'id' => rule['id'].to_s.presence || SecureRandom.uuid,
        'keywords' => keywords,
        'match' => MATCHES.include?(rule['match'].to_s) ? rule['match'].to_s : 'contains',
        'reply_text' => rule['reply_text'].to_s.strip,
        'enabled' => rule.key?('enabled') ? ActiveModel::Type::Boolean.new.cast(rule['enabled']) == true : true
      }
    end
  end

  def apply_api_attributes(attrs)
    attrs = attrs.is_a?(Hash) ? attrs.to_h.deep_stringify_keys : {}
    self.read_receipts = bool(attrs['read_receipts']) if attrs.key?('read_receipts')
    self.auto_label = bool(attrs['auto_label']) if attrs.key?('auto_label')

    if (welcome = attrs['welcome']).is_a?(Hash)
      self.welcome_enabled = bool(welcome['enabled']) if welcome.key?('enabled')
      self.welcome_text = welcome['text'].to_s.strip if welcome.key?('text')
    end

    if (away = attrs['away']).is_a?(Hash)
      self.away_enabled = bool(away['enabled']) if away.key?('enabled')
      self.away_text = away['text'].to_s.strip if away.key?('text')
      self.business_hours = self.class.normalize_business_hours(away['hours']) if away.key?('hours')
    end

    self.keyword_rules = self.class.normalize_keyword_rules(attrs['keyword_rules']) if attrs.key?('keyword_rules')

    if (email = attrs['unanswered_email']).is_a?(Hash)
      self.unanswered_email_enabled = bool(email['enabled']) if email.key?('enabled')
      self.unanswered_email_minutes = email['minutes'].to_i if email.key?('minutes')
    end
    self
  end

  def enabled_keyword_rules
    Array(keyword_rules).select { |r| r['enabled'] && Array(r['keywords']).any? && r['reply_text'].present? }
  end

  def timezone
    Whatsapp::ShopTimezone.for(shop)
  end

  def as_inbox_json
    {
      'read_receipts' => read_receipts,
      'auto_label' => auto_label,
      'welcome' => { 'enabled' => welcome_enabled, 'text' => welcome_text.to_s },
      'away' => {
        'enabled' => away_enabled,
        'text' => away_text.to_s,
        'hours' => business_hours.presence || {},
        'timezone' => timezone.tzinfo.name
      },
      'keyword_rules' => Array(keyword_rules),
      'unanswered_email' => { 'enabled' => unanswered_email_enabled, 'minutes' => unanswered_email_minutes },
      'variables' => VARIABLES
    }
  end

  private

  def bool(value)
    ActiveModel::Type::Boolean.new.cast(value) == true
  end

  def validate_business_hours
    hours = business_hours
    return if hours.blank?
    return errors.add(:business_hours, 'are invalid') unless hours.is_a?(Hash)

    hours.each do |day, ranges|
      next errors.add(:business_hours, "have an unknown day #{day}") unless DAYS.include?(day.to_s)

      Array(ranges).each do |from, to|
        unless TIME_FORMAT.match?(from.to_s) && TIME_FORMAT.match?(to.to_s)
          errors.add(:business_hours, 'must use HH:MM times')
          next
        end
        errors.add(:business_hours, 'must close after they open') unless to.to_s > from.to_s
      end
    end
  end

  def validate_keyword_rules
    rules = Array(keyword_rules)
    errors.add(:keyword_rules, "can't have more than #{MAX_KEYWORD_RULES} rules") if rules.size > MAX_KEYWORD_RULES
    rules.each do |rule|
      keywords = Array(rule['keywords'])
      errors.add(:keyword_rules, 'need at least one keyword') if keywords.empty?
      errors.add(:keyword_rules, "can have up to #{MAX_KEYWORDS_PER_RULE} keywords") if keywords.size > MAX_KEYWORDS_PER_RULE
      if keywords.any? { |k| k.to_s.length > MAX_KEYWORD_LENGTH }
        errors.add(:keyword_rules, "keywords can be up to #{MAX_KEYWORD_LENGTH} characters")
      end
      errors.add(:keyword_rules, 'need a reply') if rule['reply_text'].blank?
      if rule['reply_text'].to_s.length > MAX_TEXT_LENGTH
        errors.add(:keyword_rules, "replies can be up to #{MAX_TEXT_LENGTH} characters")
      end
    end
  end
end
