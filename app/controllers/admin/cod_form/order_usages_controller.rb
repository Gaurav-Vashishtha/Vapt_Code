# frozen_string_literal: true

module Admin
  module CodForm
    # Internal admin (Administrate) for ::CodForm::OrderUsage (ARCHITECTURE.md J.3).
    # Inside this namespace always write ::CodForm::… for the models: Admin::CodForm shadows it.
    class OrderUsagesController < Admin::ApplicationController
      include Admin::CodForm::AdminContext
    end
  end
end
