# frozen_string_literal: true

module Admin
  module CodForm
    # Shared by the Admin::CodForm::* Administrate controllers (ARCHITECTURE.md J.3):
    #   * sets the audit context (::CodForm::Current.actor / .ip, F29);
    #   * turns the text submitted by JsonTextField attributes back into JSON.
    module AdminContext
      extend ActiveSupport::Concern

      included do
        before_action :set_cod_form_audit_context
      end

      class_methods do
        # For resources whose rows decide what a shop's storefront metafield says (`features`,
        # `cap_fallback`): after a successful create / update / destroy every shop metafield is
        # rewritten by ::CodForm::MetafieldSyncAllJob, so the storefront hint is not stale until
        # the shop's next config write. The server enforces gates and caps on every request
        # regardless; this only keeps the storefront from offering what the server will refuse.
        #   expire_gates: drop the 60 s feature-gate row cache first (feature_gates).
        #   delay:        wait out the 30 s per-shop cap-state cache (plan_limits, country_groups).
        def resyncs_storefront_metafields(expire_gates: false, delay: nil)
          after_action(only: %i[create update destroy]) do
            cod_form_resync_metafields(expire_gates: expire_gates, delay: delay)
          end
        end
      end

      private

      def set_cod_form_audit_context
        ::CodForm::Current.actor = "admin:#{ENV['ADMIN_USER']}"
        ::CodForm::Current.ip = request.remote_ip
      end

      # Administrate answers a successful write with a redirect and a failed one by rendering
      # the form again. A failed enqueue must never fail the admin save.
      def cod_form_resync_metafields(expire_gates: false, delay: nil)
        return unless response.redirect?

        ::CodForm::Gates.expire_cache if expire_gates
        if delay
          ::CodForm::MetafieldSyncAllJob.perform_in(delay)
        else
          ::CodForm::MetafieldSyncAllJob.perform_async
        end
      rescue StandardError => e
        Rails.logger.error("[Admin::CodForm] metafield resync not enqueued controller=#{controller_name} #{e.class}")
      end

      # Attribute names of the dashboard that use JsonTextField.
      def json_text_attributes
        dashboard.class::ATTRIBUTE_TYPES.select { |_name, type| json_text_field?(type) }.keys.map(&:to_s)
      end

      def json_text_field?(type)
        field_class = type.respond_to?(:deferred_class) ? type.deferred_class : type
        field_class == ::JsonTextField
      end

      # Returns a plain hash: parsed JSON values must not be wrapped in ActionController::Parameters.
      def resource_params
        attributes = super.to_h
        json_text_attributes.each do |name|
          next unless attributes.key?(name) && attributes[name].is_a?(String)

          attributes[name] = parse_json_text(attributes[name])
        end
        attributes
      end

      # Invalid JSON is returned unchanged (a String), which the model's shape validation rejects.
      def parse_json_text(text)
        JSON.parse(text)
      rescue JSON::ParserError
        text
      end
    end
  end
end
