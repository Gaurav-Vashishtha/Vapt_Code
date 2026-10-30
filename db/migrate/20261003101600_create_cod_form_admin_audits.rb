# frozen_string_literal: true

# COD Form (ARCHITECTURE.md B.16, CAP-5): audit trail of internal-admin changes. No updated_at.
class CreateCodFormAdminAudits < ActiveRecord::Migration[7.2]
  def change
    create_table :cod_form_admin_audits, if_not_exists: true do |t|
      t.string :auditable_type, null: false
      t.bigint :auditable_id
      t.string :action, null: false
      t.jsonb :changed_fields, null: false, default: {}
      t.string :actor
      t.string :ip
      t.datetime :created_at, null: false
    end

    add_index :cod_form_admin_audits, %i[auditable_type auditable_id created_at],
              name: "index_cod_form_admin_audits_on_auditable_and_created_at", if_not_exists: true
  end
end
