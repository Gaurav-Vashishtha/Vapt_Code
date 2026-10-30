# frozen_string_literal: true

module CodForm
  # cod_form_shop_configs (ARCHITECTURE.md B.1). One row per shop, created lazily by .for(shop).
  class ShopConfig < ApplicationRecord
    include CodForm::AdminAudited

    self.table_name = "cod_form_shop_configs"
    self.filter_attributes = filter_attributes + %i[preview_token]

    STOREFRONT_MODE_LEGACY = "legacy"
    STOREFRONT_MODE_COD_FORM = "cod_form"
    STOREFRONT_MODES = [STOREFRONT_MODE_LEGACY, STOREFRONT_MODE_COD_FORM].freeze

    MODULE_ACCESS_DEFAULT = "default"
    MODULE_ACCESS_ON = "on"
    MODULE_ACCESS_OFF = "off"
    MODULE_ACCESS_VALUES = [MODULE_ACCESS_DEFAULT, MODULE_ACCESS_ON, MODULE_ACCESS_OFF].freeze

    admin_audited only: %i[module_access feature_overrides]

    belongs_to :shop

    validates :shop_id, uniqueness: true
    validates :storefront_mode, presence: true, inclusion: { in: STOREFRONT_MODES }
    validates :module_access, presence: true, inclusion: { in: MODULE_ACCESS_VALUES }
    validates :config_version, :metafield_synced_version,
              numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :json_shapes

    before_save :stamp_enabled_at

    scope :cod_form_mode, -> { where(storefront_mode: STOREFRONT_MODE_COD_FORM) }

    # CodForm::ShopConfig.for(shop) -> ShopConfig (K.9). Accepts a Shop or a shop id.
    def self.for(shop)
      shop_id = shop.respond_to?(:id) ? shop.id : shop
      find_or_create_by!(shop_id: shop_id)
    rescue ActiveRecord::RecordNotUnique
      find_by!(shop_id: shop_id)
    end

    def cod_form_mode?
      storefront_mode == STOREFRONT_MODE_COD_FORM
    end

    # Per-shop flag of NFR-12: "on" / "off", or "default" = follow the global default.
    # The kill switch is not part of this check (see CodForm::Availability).
    def module_enabled?
      case module_access
      when MODULE_ACCESS_ON then true
      when MODULE_ACCESS_OFF then false
      else CodForm::GlobalSetting.current.module_default_on ? true : false
      end
    end

    # Increments config_version in one SQL statement and enqueues the metafield sync.
    # Call after every admin write that affects the storefront. Returns the new version.
    # `sync: false` only records the change: the storefront keeps what it has until the merchant
    # publishes (a save in the admin; see CodFormAdmin::SyncController).
    def bump_version!(sync: true)
      self.class.where(id: id).update_all(["config_version = config_version + 1, updated_at = ?", Time.current])
      new_version = self.class.where(id: id).pick(:config_version)
      self[:config_version] = new_version
      clear_attribute_changes(%w[config_version])
      enqueue_metafield_sync if sync
      new_version
    end

    def metafield_stale?
      config_version > metafield_synced_version
    end

    def mark_metafield_synced!(version = config_version)
      update_columns(metafield_synced_version: version, metafield_synced_at: Time.current)
    end

    # Rotates the preview token (FRD-5): random 32 hex characters.
    def rotate_preview_token!
      token = SecureRandom.hex(16)
      update_columns(preview_token: token, updated_at: Time.current)
      token
    end

    def preview_token_matches?(candidate)
      return false if preview_token.blank? || candidate.blank?

      ActiveSupport::SecurityUtils.secure_compare(preview_token, candidate.to_s)
    end

    # Per-shop gate override: true / false, or nil when there is none.
    def feature_override(feature_key)
      value = feature_overrides.is_a?(Hash) ? feature_overrides[feature_key.to_s] : nil
      [true, false].include?(value) ? value : nil
    end

    private

    # Enqueued after the surrounding transaction (if any) commits, so the job never reads the
    # old config_version.
    def enqueue_metafield_sync
      target_shop_id = shop_id
      if ActiveRecord.respond_to?(:after_all_transactions_commit)
        ActiveRecord.after_all_transactions_commit { CodForm::MetafieldSyncJob.perform_async(target_shop_id) }
      else
        CodForm::MetafieldSyncJob.perform_async(target_shop_id)
      end
    end

    def stamp_enabled_at
      self.enabled_at ||= Time.current if cod_form_mode?
    end

    def json_shapes
      %i[general fraud setup_state].each do |column|
        errors.add(column, "must be a JSON object") unless self[column].is_a?(Hash)
      end

      overrides = feature_overrides
      unless overrides.is_a?(Hash) && overrides.all? { |key, value| key.is_a?(String) && [true, false].include?(value) }
        errors.add(:feature_overrides, "must be a JSON object of feature_key => true/false")
      end

      origins = allowed_origins
      unless origins.is_a?(Array) && origins.all? { |host| host.is_a?(String) }
        errors.add(:allowed_origins, "must be a JSON array of host names")
      end
    end
  end
end
