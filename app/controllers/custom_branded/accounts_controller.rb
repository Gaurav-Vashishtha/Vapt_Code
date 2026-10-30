# frozen_string_literal: true

module CustomBranded
  # Branded-portal surface for managing a client's WhatsApp numbers. Actions
  # and serialization are shared verbatim with the embedded app via
  # ::Whatsapp::AccountsActions — only the auth shell and the owner differ.
  class AccountsController < BaseController
    include ::Whatsapp::AccountsActions

    private

    # Must be defined HERE, not only in BaseController: the included concern
    # sits between this class and BaseController in the ancestor chain, so its
    # @shop default would otherwise shadow the base override.
    def whatsapp_owner
      @client
    end
  end
end
