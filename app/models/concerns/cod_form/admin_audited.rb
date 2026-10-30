# frozen_string_literal: true

module CodForm
  # Writes one cod_form_admin_audits row per internal-admin change (CAP-5, ARCHITECTURE.md B.16).
  #
  #   include CodForm::AdminAudited                     # audit create / update / destroy, all columns
  #   include CodForm::AdminAudited
  #   admin_audited only: %i[module_access feature_overrides]   # audit updates of these columns only
  #
  # Actor and ip come from CodForm::Current (set by Admin::CodForm::* controllers). An audit failure
  # never breaks the change that caused it.
  module AdminAudited
    extend ActiveSupport::Concern

    IGNORED_COLUMNS = %w[id created_at updated_at].freeze

    included do
      class_attribute :admin_audited_only, instance_writer: false, default: nil

      after_commit :write_admin_audit_create, on: :create
      after_commit :write_admin_audit_update, on: :update
      after_commit :write_admin_audit_destroy, on: :destroy
    end

    class_methods do
      def admin_audited(only: nil)
        self.admin_audited_only = only && Array(only).map(&:to_s).freeze
      end
    end

    private

    def write_admin_audit_create
      return if admin_audited_only

      changes = attributes.except(*IGNORED_COLUMNS).transform_values { |value| [nil, value] }
      write_admin_audit("create", changes)
    end

    def write_admin_audit_update
      changes = saved_changes.except(*IGNORED_COLUMNS)
      changes = changes.slice(*admin_audited_only) if admin_audited_only
      return if changes.empty?

      write_admin_audit("update", changes)
    end

    def write_admin_audit_destroy
      return if admin_audited_only

      changes = attributes.except(*IGNORED_COLUMNS).transform_values { |value| [value, nil] }
      write_admin_audit("destroy", changes)
    end

    def write_admin_audit(action, changes)
      CodForm::AdminAudit.create!(
        auditable_type: self.class.name,
        auditable_id: id,
        action: action,
        changed_fields: changes.as_json,
        actor: CodForm::Current.actor,
        ip: CodForm::Current.ip
      )
    rescue StandardError => e
      Rails.logger.error("[CodForm::AdminAudited] audit write failed type=#{self.class.name} id=#{id} #{e.class}")
      nil
    end
  end
end
