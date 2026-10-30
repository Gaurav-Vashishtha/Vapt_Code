class AddOnDeleteCascadeToSmsTemplateApprovalsSettingFk < ActiveRecord::Migration[7.2]
  def up
    # Ensure approvals are removed when their parent Setting is deleted.
    remove_foreign_key :sms_template_approvals, :settings
    add_foreign_key :sms_template_approvals, :settings, on_delete: :cascade
  end

  def down
    remove_foreign_key :sms_template_approvals, :settings
    add_foreign_key :sms_template_approvals, :settings
  end
end

