class AddPreEmailMandatoryToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :pre_email_mandatory, :boolean, default:false
  end
end
