# frozen_string_literal: true

class CreateScheduledReportDefinitions < ActiveRecord::Migration[7.2]
  BUILTIN_ROWS = [
  ].freeze

  def up
    create_table :scheduled_report_definitions do |t|
      t.string :slug, null: false
      t.string :name, null: false, default: ""
      t.string :output_format, null: false, default: "body_summary"
      t.text :sql_text
      t.timestamps
    end
    add_index :scheduled_report_definitions, :slug, unique: true

    add_reference :scheduled_shop_reports, :scheduled_report_definition, null: true, foreign_key: true

    now = Time.current
    BUILTIN_ROWS.each do |slug, name, fmt|
      execute ActiveRecord::Base.sanitize_sql_array(
        [
          "INSERT INTO scheduled_report_definitions (slug, name, output_format, sql_text, created_at, updated_at) VALUES (?, ?, ?, NULL, ?, ?)",
          slug, name, fmt, now, now,
        ],
      )
    end

    backfill_shop_report_definitions(now)

    remove_index :scheduled_shop_reports, name: "index_scheduled_shop_reports_shop_builtin_kind"
    remove_column :scheduled_shop_reports, :report_kind, :string, null: false
    remove_column :scheduled_shop_reports, :name, :string, null: false, default: ""
    remove_column :scheduled_shop_reports, :output_format, :string, null: false, default: "body_summary"
    remove_column :scheduled_shop_reports, :sql_text, :text

    add_index :scheduled_shop_reports, [:shop_id, :scheduled_report_definition_id],
              unique: true,
              name: "index_shop_reports_shop_definition_unique"

    change_column_null :scheduled_shop_reports, :scheduled_report_definition_id, false
  end

  def down
    remove_index :scheduled_shop_reports, name: "index_shop_reports_shop_definition_unique"
    add_column :scheduled_shop_reports, :report_kind, :string
    add_column :scheduled_shop_reports, :name, :string, default: "", null: false
    add_column :scheduled_shop_reports, :output_format, :string, default: "body_summary", null: false
    add_column :scheduled_shop_reports, :sql_text, :text

    execute <<-SQL.squish
      UPDATE scheduled_shop_reports ssr
      SET report_kind = CASE
        WHEN d.slug LIKE 'legacy_custom_%' THEN 'custom_sql'
        ELSE d.slug
      END,
      name = d.name,
      output_format = d.output_format,
      sql_text = d.sql_text
      FROM scheduled_report_definitions d
      WHERE d.id = ssr.scheduled_report_definition_id
    SQL

    change_column_null :scheduled_shop_reports, :report_kind, false
    remove_reference :scheduled_shop_reports, :scheduled_report_definition, foreign_key: true

    drop_table :scheduled_report_definitions

    add_index :scheduled_shop_reports, [:shop_id, :report_kind],
              unique: true,
              name: "index_scheduled_shop_reports_shop_builtin_kind",
              where: "((report_kind)::text <> 'custom_sql'::text)"
  end

  private

  def backfill_shop_report_definitions(now)
    conn = ActiveRecord::Base.connection

    conn.select_all(
      "SELECT id, shop_id, name, output_format, sql_text FROM scheduled_shop_reports WHERE report_kind = 'custom_sql'",
    ).each do |row|
      sid = row["id"]
      slug = "legacy_custom_#{sid}"
      name = row["name"].presence || "Custom report #{sid}"
      fmt = row["output_format"].presence || "body_summary"
      sql = row["sql_text"]

      sql_insert = ActiveRecord::Base.sanitize_sql_array(
        [
          "INSERT INTO scheduled_report_definitions (slug, name, output_format, sql_text, created_at, updated_at) " \
            "VALUES (?, ?, ?, ?, ?, ?) RETURNING id",
          slug, name, fmt, sql, now, now,
        ],
      )
      def_id = conn.exec_query(sql_insert).first["id"]

      conn.execute(
        ActiveRecord::Base.sanitize_sql_array(
          [
            "UPDATE scheduled_shop_reports SET scheduled_report_definition_id = ? WHERE id = ?",
            def_id, sid,
          ],
        ),
      )
    end

    conn.execute(<<-SQL.squish)
      UPDATE scheduled_shop_reports ssr
      SET scheduled_report_definition_id = d.id
      FROM scheduled_report_definitions d
      WHERE ssr.report_kind = d.slug
        AND ssr.report_kind <> 'custom_sql'
    SQL
  end
end
