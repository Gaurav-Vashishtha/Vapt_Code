# frozen_string_literal: true

module CustomBranded
  # Branded-portal surface for template CRUD/sync against Meta. Shared verbatim
  # with the embedded app via ::Whatsapp::TemplatesActions.
  class TemplatesController < BaseController
    include ::Whatsapp::TemplatesActions

    private

    # Must be defined HERE, not only in BaseController: the included concern
    # sits between this class and BaseController in the ancestor chain, so its
    # @shop default would otherwise shadow the base override.
    def whatsapp_owner
      @client
    end
  end
end
