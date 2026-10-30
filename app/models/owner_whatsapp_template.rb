# frozen_string_literal: true

class OwnerWhatsappTemplate < ApplicationRecord
  has_many :merchant_whatsapp_rules, dependent: :nullify

  CATEGORIES = %w[UTILITY MARKETING].freeze

  validates :name, presence: true
  validates :language, presence: true

  scope :approved, -> { where(status: "approved") }

  def approved?
    status.to_s == "approved"
  end

  def buttons_list
    Array(buttons)
  end

  # Buttons may live in the `buttons` column (builder-created templates) or
  # only inside the synced Meta components — check both.
  def all_buttons
    list = buttons_list
    return list if list.present?

    comp = Array(components).find { |c| c.is_a?(Hash) && c["type"].to_s.casecmp?("BUTTONS") }
    Array(comp && (comp["buttons"] || comp[:buttons]))
  end

  # Meta requires one parameter per URL button whose url contains {{N}}.
  def dynamic_url_button_indexes
    all_buttons.each_with_index.filter_map do |b, i|
      next unless b.is_a?(Hash)

      type = (b["type"] || b[:type]).to_s
      url = (b["url"] || b[:url]).to_s
      i if type.casecmp?("URL") && url.include?("{{")
    end
  end

  def variable_positions
    (variable_mapping || {}).keys.map(&:to_i).sort
  end
end
