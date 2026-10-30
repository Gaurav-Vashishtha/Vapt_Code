# frozen_string_literal: true

module Admin
  module CodForm
    # Internal admin (Administrate) for ::CodForm::FeatureGate (ARCHITECTURE.md J.3).
    # Inside this namespace always write ::CodForm::… for the models: Admin::CodForm shadows it.
    class FeatureGatesController < Admin::ApplicationController
      include Admin::CodForm::AdminContext

      # A gate decides the `features` list of every shop metafield.
      resyncs_storefront_metafields expire_gates: true
    end
  end
end
