# frozen_string_literal: true

# COD Form (ARCHITECTURE.md B.9, FRD-6): log of blocked / rejected attempts. No updated_at.
class CreateCodFormRejections < ActiveRecord::Migration[7.2]
  def change
    create_table :cod_form_rejections, if_not_exists: true do |t|
      t.bigint :shop_id, null: false
      t.string :session_public_id
      t.string :reason_code, null: false
      t.string :stage, null: false
      t.string :subject_kind
      t.string :subject_masked
      t.jsonb :detail, null: false, default: {}
      t.string :ip
      t.datetime :created_at, null: false
    end

    add_index :cod_form_rejections, %i[shop_id created_at],
              name: "index_cod_form_rejections_on_shop_id_and_created_at", if_not_exists: true
  end
end
