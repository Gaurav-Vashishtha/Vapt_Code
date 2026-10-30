class CreateSsoSessions < ActiveRecord::Migration[7.2]
  def up
    return if table_exists?(:sso_sessions)

    create_table :sso_sessions do |t|
      t.string :session_token, null: false
      t.string :phone, null: false
      t.string :country_code
      t.datetime :expires_at, null: false
      t.timestamps
    end

    add_index :sso_sessions, :session_token, unique: true
    add_index :sso_sessions, :phone
    add_index :sso_sessions, :expires_at
  end

  def down
    drop_table :sso_sessions if table_exists?(:sso_sessions)
  end
end
