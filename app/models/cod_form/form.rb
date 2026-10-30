# frozen_string_literal: true

module CodForm
  # cod_forms (ARCHITECTURE.md B.2, C.2). The storefront reads only published_config.
  class Form < ApplicationRecord
    self.table_name = "cod_forms"

    STATUS_ACTIVE = "active"
    STATUS_ARCHIVED = "archived"
    STATUSES = [STATUS_ACTIVE, STATUS_ARCHIVED].freeze
    TEMPLATE_KEYS = %w[classic minimal bold compact].freeze
    DEFAULT_NAME = "Default form"
    MAX_FORMS_PER_SHOP = 5

    belongs_to :shop

    # Engine errors ([{"path","code"}]) of the last failed #publish!.
    attr_reader :publish_errors

    validates :name, presence: true, length: { maximum: 120 }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :template_key, inclusion: { in: TEMPLATE_KEYS }, allow_nil: true
    validates :position, :published_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :json_shapes
    validate :one_default_per_shop
    validate :default_form_stays_active
    validate :forms_per_shop_limit

    scope :active, -> { where(status: STATUS_ACTIVE) }
    scope :archived, -> { where(status: STATUS_ARCHIVED) }
    scope :ordered, -> { order(position: :asc, id: :asc) }
    scope :defaults, -> { where(is_default: true) }

    # The shop's default form; created (and published with the default config) on first use.
    def self.default_for(shop)
      shop_id = shop.respond_to?(:id) ? shop.id : shop
      existing = where(shop_id: shop_id, is_default: true).first
      return existing if existing

      # New stores start on the Express theme.
      config = CodForm::Engine::Defaults.new_form_config
      create!(shop_id: shop_id, name: DEFAULT_NAME, is_default: true, status: STATUS_ACTIVE,
              draft_config: config, published_config: config, published_version: 1,
              published_at: Time.current)
    rescue ActiveRecord::RecordNotUnique
      where(shop_id: shop_id, is_default: true).first!
    end

    def active?
      status == STATUS_ACTIVE
    end

    def archived?
      status == STATUS_ARCHIVED
    end

    def published?
      published_version.to_i.positive?
    end

    def unpublished_changes?
      draft_config != published_config
    end

    # Copies draft_config -> published_config after CodForm::Engine::FormConfig.normalize returns no
    # errors, sets published_at, increments published_version and bumps the shop config_version (C.2).
    # Raises ActiveRecord::RecordInvalid when the draft has errors (see #publish_errors).
    def publish!
      result = CodForm::Engine::FormConfig.normalize(draft_config)
      @publish_errors = Array(result["errors"])
      if @publish_errors.any?
        errors.add(:draft_config, "has errors and cannot be published")
        raise ActiveRecord::RecordInvalid, self
      end

      normalized = result["config"]
      update!(draft_config: normalized, published_config: normalized,
              published_version: published_version.to_i + 1, published_at: Time.current)
      CodForm::ShopConfig.for(shop_id).bump_version!
      self
    end

    private

    def json_shapes
      %i[targeting draft_config published_config].each do |column|
        errors.add(column, "must be a JSON object") unless self[column].is_a?(Hash)
      end
    end

    def one_default_per_shop
      return unless is_default && shop_id

      others = self.class.where(shop_id: shop_id, is_default: true)
      others = others.where.not(id: id) if persisted?
      errors.add(:is_default, "is already set on another form of this shop") if others.exists?
    end

    def default_form_stays_active
      errors.add(:status, "cannot be archived for the default form") if is_default && archived?
    end

    def forms_per_shop_limit
      return unless shop_id && active?
      return unless new_record? || status_changed?

      others = self.class.where(shop_id: shop_id).where.not(status: STATUS_ARCHIVED)
      others = others.where.not(id: id) if persisted?
      return if others.count < MAX_FORMS_PER_SHOP

      errors.add(:base, "a shop can have at most #{MAX_FORMS_PER_SHOP} forms")
    end
  end
end
