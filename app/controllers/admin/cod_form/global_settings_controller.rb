# frozen_string_literal: true

module Admin
  module CodForm
    # Internal admin (Administrate) for the ::CodForm::GlobalSetting singleton (ARCHITECTURE.md J.3).
    # Inside this namespace always write ::CodForm::… for the models: Admin::CodForm shadows it.
    class GlobalSettingsController < Admin::ApplicationController
      include Admin::CodForm::AdminContext

      RESYNC_COLUMNS = %w[kill_switch module_default_on].freeze

      # Flipping the kill switch (or the module default) changes `enabled` in every shop's
      # metafield: ::CodForm::MetafieldSyncAllJob rewrites them (ARCHITECTURE.md A.3).
      def update
        super
        return unless requested_resource.errors.empty?
        return unless (requested_resource.saved_changes.keys & RESYNC_COLUMNS).any?

        begin
          ::CodForm::MetafieldSyncAllJob.perform_async
        rescue StandardError => e
          Rails.logger.error("[Admin::CodForm::GlobalSettings] metafield resync not enqueued #{e.class}")
        end
      end
    end
  end
end
