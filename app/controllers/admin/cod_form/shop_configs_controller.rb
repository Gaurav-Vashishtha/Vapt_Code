# frozen_string_literal: true

module Admin
  module CodForm
    # Internal admin (Administrate) for ::CodForm::ShopConfig (ARCHITECTURE.md J.3).
    # Editable: module_access, feature_overrides, storefront_mode.
    # Inside this namespace always write ::CodForm::… for the models: Admin::CodForm shadows it.
    class ShopConfigsController < Admin::ApplicationController
      include Admin::CodForm::AdminContext

      # All three editable attributes change what the storefront gets, so a successful update
      # bumps config_version, which re-syncs the shop metafield.
      def update
        super
        return unless requested_resource.errors.empty? && requested_resource.saved_changes.present?

        begin
          requested_resource.bump_version!
        rescue StandardError => e
          Rails.logger.error("[Admin::CodForm::ShopConfigs] bump_version failed id=#{requested_resource.id} #{e.class}")
        end
      end
    end
  end
end
