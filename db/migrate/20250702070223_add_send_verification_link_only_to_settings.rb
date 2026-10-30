class AddSendVerificationLinkOnlyToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :send_verification_link_only, :boolean, default:false
  end
end
