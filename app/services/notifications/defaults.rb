module Notifications
  # Placeholders used when a value for a customer notification can't be
  # resolved — typically because the Shopify Admin API read failed (401 after a
  # token was revoked out of band, 404, throttling) and the local
  # OrderConfirmation row doesn't carry it either.
  #
  # Sending "Hi ," or a template with an empty variable is worse than sending a
  # neutral placeholder: MSG91/Meta reject blank template variables outright, so
  # a blank value means no message at all.
  module Defaults
    NAME = 'Customer'.freeze
    PLACEHOLDER = '-'.freeze

    class << self
      # Full recipient name, e.g. "Aman Singh" → "Aman Singh", blank → "Customer"
      def name(value)
        value.to_s.strip.presence || NAME
      end

      # First word of the recipient name (what most SMS templates use),
      # blank → "Customer"
      def first_name(value)
        value.to_s.strip.partition(' ').first.presence || NAME
      end

      # Order number, tracking number, tracking URL, …  blank → "-"
      def value(raw)
        raw.to_s.strip.presence || PLACEHOLDER
      end
    end
  end
end
