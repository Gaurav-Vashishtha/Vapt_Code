class AddOrderConfirmationTemplateToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :order_confirmation_template, :string
    add_column :settings, :pre_redirect_text, :string
  end
end
