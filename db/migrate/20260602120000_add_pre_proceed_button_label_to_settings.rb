class AddPreProceedButtonLabelToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :pre_proceed_button_label, :string, default: 'Proceed to Payment'
  end
end
