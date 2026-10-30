class CreateSmsTemplateApprovalTables < ActiveRecord::Migration[7.2]
  def change
    create_table :sms_template_type_configs do |t|
      t.string :key, null: false
      t.string :display_name, null: false
      t.string :target_column, null: false
      t.jsonb :allowed_variables, default: [], null: false
      t.integer :max_variables, default: 0, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    add_index :sms_template_type_configs, :key, unique: true
    add_index :sms_template_type_configs, :active

    create_table :sms_template_approvals do |t|
      t.references :shop, null: false, foreign_key: true
      t.references :setting, null: false, foreign_key: true
      t.string :template_type_key, null: false
      t.string :target_column, null: false
      t.text :body, null: false
      t.jsonb :variables_used, default: [], null: false
      t.integer :max_variables, default: 0, null: false
      t.string :status, null: false, default: "pending"
      t.string :submitted_by
      t.datetime :submitted_at, null: false
      t.string :reviewed_by
      t.datetime :reviewed_at
      t.text :review_reason
      t.datetime :applied_to_settings_at
      t.timestamps
    end

    add_index :sms_template_approvals, [:shop_id, :template_type_key, :status], name: "idx_sms_template_approvals_shop_type_status"
    add_index :sms_template_approvals, :status

    reversible do |dir|
      dir.up do
        now_sql = Time.current.utc.strftime("%Y-%m-%d %H:%M:%S")
        execute <<~SQL.squish
          INSERT INTO sms_template_type_configs
            (key, display_name, target_column, allowed_variables, max_variables, active, created_at, updated_at)
          VALUES
            ('order_confirmation', 'Order Placed', 'order_confirmation_template', '["name","amount","store","number"]'::jsonb, 3, TRUE, '#{now_sql}', '#{now_sql}'),
            ('order_fulfilment', 'Order Fulfilment', 'fulfilment_template', '["name","number","tracking_url","tracking_number","store"]'::jsonb, 3, TRUE, '#{now_sql}', '#{now_sql}'),
            ('abandoned_checkout', 'Abandoned Checkout', 'abandoned_template', '["name","a_url"]'::jsonb, 2, TRUE, '#{now_sql}', '#{now_sql}'),
            ('retry_otp', 'Retry OTP', 'retry_template', '["otp","store","link"]'::jsonb, 2, TRUE, '#{now_sql}', '#{now_sql}'),
            ('cancel_order', 'Cancel Order', 'cancel_template', '["store","number"]'::jsonb, 2, TRUE, '#{now_sql}', '#{now_sql}'),
            ('otp', 'OTP Verification', 'template', '["otp","store"]'::jsonb, 2, TRUE, '#{now_sql}', '#{now_sql}')
        SQL
      end
    end
  end
end
