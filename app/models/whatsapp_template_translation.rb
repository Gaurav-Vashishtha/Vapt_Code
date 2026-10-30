# frozen_string_literal: true

# One translation of a COD King default-number MSG91 WhatsApp template (the shared namespace every
# shop without its own number sends from). Approved once, usable by every such shop.
#
# The template keeps its English name; only the language code differs, so senders switch language
# without switching template name (see Whatsapp::TemplateLanguage).
class WhatsappTemplateTranslation < ApplicationRecord
  # Languages this system translates and manages. Add a language here (Meta language code => label)
  # and it appears in the support dashboard and, once approved, in the merchant picker.
  LANGUAGES = {
    "ur" => { name: "Urdu", native: "اردو", rtl: true },
    "ar" => { name: "Arabic", native: "العربية", rtl: true }
  }.freeze
  SOURCE_LANGUAGE = "en"

  STATUSES = %w[not_started draft submitted pending approved rejected failed].freeze
  EDITABLE_STATUSES = %w[not_started draft rejected failed].freeze

  validates :template_name, presence: true
  validates :language, inclusion: { in: LANGUAGES.keys }
  validates :status, inclusion: { in: STATUSES }
  validates :language, uniqueness: { scope: :template_name }

  scope :approved, -> { where(status: "approved") }

  after_commit :clear_language_cache

  def self.language_name(code)
    code.to_s == SOURCE_LANGUAGE ? "English" : LANGUAGES.dig(code.to_s, :name) || code.to_s
  end

  def self.rtl?(code)
    LANGUAGES.dig(code.to_s, :rtl) == true
  end

  def editable?
    EDITABLE_STATUSES.include?(status)
  end

  def approved?
    status == "approved"
  end

  def components_list
    Array(components)
  end

  def source_components_list
    Array(source_components)
  end

  private

  def clear_language_cache
    Whatsapp::TemplateLanguage.clear_cache!
  end
end
