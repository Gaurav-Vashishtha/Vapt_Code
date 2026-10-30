# frozen_string_literal: true

module CodForm
  # Request-scoped context for the internal-admin audit trail (ARCHITECTURE.md B.16, J.3).
  # Set by the Admin::CodForm::* controllers; read by CodForm::AdminAudited.
  class Current < ActiveSupport::CurrentAttributes
    attribute :actor, :ip
  end
end
