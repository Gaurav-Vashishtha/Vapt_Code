class AddPreSkipBtnTextToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :pre_skip_btn_text, :string,  deafult: 'Skip and place Non-COD Order'
    Setting.where(pre_skip_btn_text: nil).update_all(pre_skip_btn_text: 'Skip and place Non-COD Order')
  end
end
