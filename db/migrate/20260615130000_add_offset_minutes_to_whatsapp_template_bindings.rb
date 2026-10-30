class AddOffsetMinutesToWhatsappTemplateBindings < ActiveRecord::Migration[7.2]
  # Lets bindings carry a "send X minutes after the trigger" delay. Used by
  # COD verification (default 0 = immediate, but merchants can buffer to give
  # buyers a moment) and is the foundation for the upcoming abandoned-cart
  # multi-stage reminders.
  def change
    add_column :whatsapp_template_bindings, :offset_minutes, :integer, null: false, default: 0
  end
end
