# frozen_string_literal: true

module CodForm
  # cod_offer_ab_tests (ARCHITECTURE.md B.6, OFF-12).
  class AbTest < ApplicationRecord
    self.table_name = "cod_offer_ab_tests"

    STATUS_DRAFT = "draft"
    STATUS_RUNNING = "running"
    STATUS_STOPPED = "stopped"
    STATUSES = [STATUS_DRAFT, STATUS_RUNNING, STATUS_STOPPED].freeze
    MIN_VARIANTS = 2
    MAX_VARIANTS = 4

    belongs_to :shop
    has_many :offers, class_name: "CodForm::Offer", foreign_key: :ab_test_id, dependent: :nullify

    validates :name, presence: true, length: { maximum: 255 }
    validates :offer_type, presence: true, inclusion: { in: CodForm::Offer::OFFER_TYPES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validate :variants_shape
    validate :variants_immutable_once_started
    validate :winner_is_a_variant

    scope :running, -> { where(status: STATUS_RUNNING) }

    def running?
      status == STATUS_RUNNING
    end

    def variant_keys
      Array(variants).filter_map { |variant| variant["key"] if variant.is_a?(Hash) }
    end

    def start!
      update!(status: STATUS_RUNNING, started_at: started_at || Time.current, stopped_at: nil)
    end

    def stop!(winner_key: nil)
      update!(status: STATUS_STOPPED, stopped_at: Time.current, winner_key: winner_key || self.winner_key)
    end

    # Engine representation used by CodForm::Engine::AbTest.assign, string keys.
    def to_engine_hash
      { "id" => id, "offer_type" => offer_type, "status" => status, "variants" => variants }
    end

    private

    def variants_shape
      list = variants
      unless list.is_a?(Array) && list.size.between?(MIN_VARIANTS, MAX_VARIANTS) && list.all? { |v| v.is_a?(Hash) }
        errors.add(:variants, "must be a JSON array of #{MIN_VARIANTS} to #{MAX_VARIANTS} variants")
        return
      end

      keys = list.map { |variant| variant["key"] }
      unless keys.all? { |key| key.is_a?(String) && !key.empty? } && keys.uniq.size == keys.size
        errors.add(:variants, "must have unique, non-empty keys")
      end

      weights = list.map { |variant| variant["weight"] }
      unless weights.all? { |weight| weight.is_a?(Integer) && weight >= 0 } && weights.sum == 100
        errors.add(:variants, "weights must be integers that sum to 100")
      end

      unless list.all? { |variant| variant["offer_id"].nil? || variant["offer_id"].is_a?(Integer) }
        errors.add(:variants, "offer_id must be an offer id or null")
      end
    end

    def variants_immutable_once_started
      return unless persisted? && variants_changed? && started_at_was.present?

      errors.add(:variants, "cannot be changed after the test has started")
    end

    def winner_is_a_variant
      return if winner_key.blank? || variant_keys.include?(winner_key)

      errors.add(:winner_key, "is not one of the variant keys")
    end
  end
end
