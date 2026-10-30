# frozen_string_literal: true

module Admin
  module CodForm
    # Internal admin (Administrate) for ::CodForm::PlanLimit (ARCHITECTURE.md J.3).
    # Inside this namespace always write ::CodForm::… for the models: Admin::CodForm shadows it.
    class PlanLimitsController < Admin::ApplicationController
      include Admin::CodForm::AdminContext

      # ::CodForm::CapService caches a shop's cap state for 30 s; the re-sync waits it out.
      CAP_CACHE_WAIT = 35

      # A cap row decides `cap_fallback` in shop metafields.
      resyncs_storefront_metafields delay: CAP_CACHE_WAIT
    end
  end
end
