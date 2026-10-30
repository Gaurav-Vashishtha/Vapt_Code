class AddVerificationTagToSettings < ActiveRecord::Migration[7.2]
  DEFAULT_TAG = '✅ COD-Verified'.freeze

  class Setting < ApplicationRecord
    self.table_name = 'settings'
  end

  def up
    add_column :settings, :verification_tag, :string, default: DEFAULT_TAG, null: false

    Setting.reset_column_information
    Setting.where(verification_tag: [nil, '']).update_all(verification_tag: DEFAULT_TAG)
  end

  def down
    remove_column :settings, :verification_tag
  end
end

