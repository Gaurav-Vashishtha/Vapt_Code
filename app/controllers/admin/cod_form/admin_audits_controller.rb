# frozen_string_literal: true

module Admin
  module CodForm
    # Internal admin (Administrate) for ::CodForm::AdminAudit (ARCHITECTURE.md J.3).
    # Inside this namespace always write ::CodForm::… for the models: Admin::CodForm shadows it.
    class AdminAuditsController < Admin::ApplicationController
      include Admin::CodForm::AdminContext
    end
  end
end
