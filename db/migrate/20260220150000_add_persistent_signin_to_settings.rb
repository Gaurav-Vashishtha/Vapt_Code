# frozen_string_literal: true

class AddPersistentSigninToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :persistent_signin, :boolean, default: false, null: false
  end
end
