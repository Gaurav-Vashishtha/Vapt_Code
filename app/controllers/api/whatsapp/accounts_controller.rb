module Api
  module Whatsapp
    # Embedded-app surface for managing a shop's WhatsApp numbers. All actions
    # and serialization live in ::Whatsapp::AccountsActions, shared with the
    # partner-facing branded portal (CustomBranded::AccountsController) — only
    # the authentication shell (Shopify embedded session) differs.
    class AccountsController < AuthenticatedController
      include ::Whatsapp::AccountsActions
    end
  end
end
