module Whatsapp
  # Curated catalog of legacy (MSG91-backed) prepaid reminder templates.
  # Distinct from `Whatsapp::TemplateLibrary` (BSP / merchant-owned WABA).
  #
  # Each entry maps a friendly `key` shown in the merchant UI to the actual
  # MSG91 template name registered on the operator side. The merchant picks
  # a template by key; we send via the matching `msg91_template_name`.
  #
  # Preview URLs are placeholder.co images for now — swap to real renders
  # (or AWS S3 hosted PNGs) without changing this contract.
  class PrepaidTemplateLibrary
    ENTRIES = [
      {
        key: 'cod_prepaid_english',
        name: 'COD-Prepaid-English',
        description: 'English prepaid conversion reminder. Standard CTA and friendly tone.',
        preview_image_url: 'https://cdn.shopify.com/s/files/1/0743/3119/3628/files/prepaid_en.png?v=1780473153',
        msg91_template_name: 'order_tracking_new',
        languages: %w[en]
      },
      {
        key: 'cod_prepaid_hindi',
        name: 'COD-Prepaid-Hindi',
        description: 'Hindi prepaid conversion reminder. Same layout as the English variant, translated copy.',
        preview_image_url: 'https://cdn.shopify.com/s/files/1/0743/3119/3628/files/prepaid_hi.png?v=1780473154',
        msg91_template_name: 'order_tracking_hindi',
        languages: %w[hi]
      }
    ].freeze

    def self.all
      ENTRIES
    end

    def self.find(key)
      ENTRIES.find { |e| e[:key] == key.to_s }
    end

    # Returns the actual MSG91 template name for sending, or nil if the
    # given key isn't in the library.
    def self.msg91_name_for(key)
      find(key)&.dig(:msg91_template_name)
    end

    # `msg91_template_name` is included so the frontend can reverse-map
    # `setting.whatsapp_prepaid_template_name` (raw MSG91 name) back to the
    # library entry's friendly `name` for display as the "shop default".
    # Without it, the UI shows the raw operator name and merchants get confused.
    def self.as_json
      ENTRIES.map do |e|
        {
          key: e[:key],
          name: e[:name],
          description: e[:description],
          preview_image_url: e[:preview_image_url],
          languages: e[:languages],
          msg91_template_name: e[:msg91_template_name]
        }
      end
    end
  end
end
