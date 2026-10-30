class CreateNotificationTemplates < ActiveRecord::Migration[6.1]
  def change
    create_table :notification_templates do |t|
      t.string :name, null: false, index: { unique: true }   # e.g. welcome_email
      t.string :subject, null: false                         # e.g. Welcome to COD King
      t.string :view_file, null: false                       # e.g. welcome_email
      t.string :trigger_type, null: false                    # e.g. time_after_signup
      t.jsonb :trigger_params, default: {}                   # e.g. { days: 1, hour: 10 }
      t.boolean :active, default: true

      t.timestamps
    end
  end
end
