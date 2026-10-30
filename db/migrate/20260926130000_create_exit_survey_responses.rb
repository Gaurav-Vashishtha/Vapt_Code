# Exit survey answers (form linked from the uninstall email), one row per
# submission. A brand-new table on purpose: no ALTER on uninstalled_shops (whose
# ACCESS EXCLUSIVE lock timed out in the 2026-09-26 release) and no foreign key
# to it either — adding one takes a SHARE ROW EXCLUSIVE lock on the referenced
# table. uninstalled_shop_id is a plain indexed column.
class CreateExitSurveyResponses < ActiveRecord::Migration[7.2]
  def up
    return if table_exists?(:exit_survey_responses)

    create_table :exit_survey_responses do |t|
      t.bigint :uninstalled_shop_id
      t.string :shop_domain, null: false
      t.string :reason
      t.text :feedback
      t.string :switched_to
      t.string :missing_feature
      t.string :win_back
      t.string :return_likelihood
      t.boolean :wants_callback, default: false, null: false
      t.string :callback_phone
      t.datetime :submitted_at, null: false
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end
    add_index :exit_survey_responses, :uninstalled_shop_id
    add_index :exit_survey_responses, :shop_domain
    add_index :exit_survey_responses, :submitted_at
    add_index :exit_survey_responses, %i[reason submitted_at]
  end

  def down
    drop_table :exit_survey_responses if table_exists?(:exit_survey_responses)
  end
end
