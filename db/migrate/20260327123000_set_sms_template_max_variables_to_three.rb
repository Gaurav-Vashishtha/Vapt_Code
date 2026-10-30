class SetSmsTemplateMaxVariablesToThree < ActiveRecord::Migration[7.2]
  def up
    execute <<~SQL
      UPDATE sms_template_type_configs
      SET max_variables = 3, updated_at = NOW()
    SQL
  end

  def down
    # Intentionally no-op: previous max values are not reliably recoverable.
  end
end
