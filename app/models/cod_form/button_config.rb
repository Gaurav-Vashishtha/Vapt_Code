# frozen_string_literal: true

module CodForm
  # cod_button_configs (ARCHITECTURE.md B.3, C.1.2). One row per shop.
  class ButtonConfig < ApplicationRecord
    self.table_name = "cod_button_configs"

    PRESETS = %w[A B C].freeze
    DEFAULT_PRESET = "B"
    CONFIG_KEYS = %w[button sticky cart theme quantity_widget].freeze

    belongs_to :shop

    validates :shop_id, uniqueness: true
    validates :preset, presence: true, inclusion: { in: PRESETS }
    validate :config_shape

    # The shop's button config; created with the engine defaults (preset B) on first use.
    def self.for(shop)
      shop_id = shop.respond_to?(:id) ? shop.id : shop
      existing = find_by(shop_id: shop_id)
      return existing if existing

      create!(shop_id: shop_id, preset: DEFAULT_PRESET, config: CodForm::Engine::Defaults.button_config)
    rescue ActiveRecord::RecordNotUnique
      find_by!(shop_id: shop_id)
    end

    private

    def config_shape
      errors.add(:config, "must be a JSON object") unless config.is_a?(Hash)
    end
  end
end
