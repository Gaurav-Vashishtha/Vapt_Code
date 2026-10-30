# frozen_string_literal: true

require "test_helper"

# Covers CodForm::AdminAudit and the CodForm::AdminAudited concern.
class CodForm::AdminAuditTest < ActiveSupport::TestCase
  setup do
    CodForm::Current.actor = "admin:test"
    CodForm::Current.ip = "198.51.100.7"
  end

  test "create, update and destroy of an audited model are recorded with actor and ip" do
    gate = CodForm::FeatureGate.create!(feature_key: "ws1_audit_gate")
    gate.update!(min_tier: "pro")
    gate.destroy!

    audits = CodForm::AdminAudit.where(auditable_type: "CodForm::FeatureGate", auditable_id: gate.id).order(:id)
    assert_equal %w[create update destroy], audits.map(&:action)
    assert_equal({ "min_tier" => %w[free pro] }, audits[1].changed_fields)
    assert_equal ["admin:test"], audits.map(&:actor).uniq
    assert_equal ["198.51.100.7"], audits.map(&:ip).uniq
  end

  test "ShopConfig is audited for module_access and feature_overrides only" do
    config = CodForm::ShopConfig.for(shops(:regular_shop))
    config.update!(storefront_mode: "cod_form", general: { "countries" => ["HU"] })
    scope = CodForm::AdminAudit.where(auditable_type: "CodForm::ShopConfig", auditable_id: config.id)
    assert_equal 0, scope.count

    config.update!(module_access: "on", storefront_mode: "legacy")
    assert_equal 1, scope.count
    assert_equal({ "module_access" => %w[default on] }, scope.first.changed_fields)
  end

  test "audit rows are read-only" do
    audit = CodForm::AdminAudit.create!(auditable_type: "CodForm::PlanLimit", auditable_id: 1, action: "update")
    assert_raises(ActiveRecord::ReadOnlyRecord) { audit.update!(action: "destroy") }
  end
end
