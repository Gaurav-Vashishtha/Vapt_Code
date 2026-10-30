# frozen_string_literal: true

class AddPauseToWhatsappTemplateBindings < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    with_lock_retries do
      add_column :whatsapp_template_bindings, :paused_at, :datetime
      add_column :whatsapp_template_bindings, :resumed_at, :datetime
      add_column :whatsapp_template_bindings, :last_paused_at, :datetime
    end
  end
end
