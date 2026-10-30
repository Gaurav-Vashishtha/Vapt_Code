# frozen_string_literal: true

module Api
  module Form
    # POST /api/form/contact (D.3, ABN-1). Saves what the buyer typed so far on the session
    # (normalised phone / email); nothing else happens here.
    class ContactsController < BaseController
      CONTACT_KEYS = %w[first_name last_name email].freeze
      ADDRESS_KEYS = %w[country province city zip address1 address2].freeze

      def create
        session = form_session
        return render_ok if session.order_id.present?

        raw_contact = body["contact"].is_a?(Hash) ? body["contact"] : {}
        raw_address = body["address"].is_a?(Hash) ? body["address"] : {}
        country = (body["country"] || raw_address["country"] || session.country_code).to_s.strip.upcase
        country = session.country_code.to_s unless country.match?(/\A[A-Z]{2}\z/)

        contact = session.contact.is_a?(Hash) ? session.contact.dup : {}
        CONTACT_KEYS.each { |key| contact[key] = clean(raw_contact[key]) if raw_contact.key?(key) }
        contact["email"] = contact["email"].to_s.downcase if contact.key?("email")

        attrs = {}
        phone_locked = session.otp_verified_at.present?
        if raw_contact.key?("phone") && !phone_locked
          parsed = CodForm::Engine::Phone.validate(
            raw: raw_contact["phone"].to_s[0, 40], country: country,
            rules: CodForm::Engine::CountrySchema.phone_rules(country: country)
          )
          if parsed["valid"] == true
            contact["phone_e164"] = parsed["e164"]
            contact["phone_national"] = parsed["national"]
            attrs[:phone_normalized] = parsed["digits"]
          end
        end

        address = session.address.is_a?(Hash) ? session.address.dup : {}
        ADDRESS_KEYS.each { |key| address[key] = clean(raw_address[key]) if raw_address.key?(key) }
        address["country"] = country if country.match?(/\A[A-Z]{2}\z/)

        attrs[:contact] = contact
        attrs[:address] = address
        attrs[:email_normalized] = contact["email"].presence if contact.key?("email")
        attrs[:country_code] = country if country.match?(/\A[A-Z]{2}\z/)
        attrs[:updated_at] = Time.current
        session.update_columns(attrs)
        render_ok
      end

      private

      def clean(value)
        value.is_a?(String) || value.is_a?(Numeric) ? value.to_s.strip[0, 255] : ""
      end
    end
  end
end
