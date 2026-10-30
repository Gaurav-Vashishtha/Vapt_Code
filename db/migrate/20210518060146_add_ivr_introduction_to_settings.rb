class AddIvrIntroductionToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :ivr_introduction, :string
    add_column :settings, :ivr_confirm_message, :string
    add_column :settings, :ivr_cancel_message, :string
  end
end
