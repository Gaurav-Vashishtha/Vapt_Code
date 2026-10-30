module Api
  module Whatsapp
    # Embedded-app surface for template CRUD/sync against Meta. All actions and
    # serialization live in ::Whatsapp::TemplatesActions, shared with the
    # partner-facing branded portal (CustomBranded::TemplatesController) — only
    # the authentication shell (Shopify embedded session) differs.
    class TemplatesController < AuthenticatedController
      include ::Whatsapp::TemplatesActions
    end
  end
end
