# frozen_string_literal: true

# COD Form (ARCHITECTURE.md B.17, ANL-5): daily funnel rollups, one dimension at a time.
class CreateCodFormDailyStats < ActiveRecord::Migration[7.2]
  def change
    create_table :cod_form_daily_stats, if_not_exists: true do |t|
      t.bigint :shop_id, null: false
      t.date :stat_date, null: false
      t.string :dimension, null: false, default: "all"
      t.string :dimension_value, null: false, default: ""
      t.jsonb :metrics, null: false, default: {}
      t.timestamps null: false
    end

    add_index :cod_form_daily_stats, %i[shop_id stat_date dimension dimension_value], unique: true,
              name: "index_cod_form_daily_stats_unique", if_not_exists: true
  end
end
