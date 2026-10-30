class AddHeaderMediaToWhatsappTemplates < ActiveRecord::Migration[7.2]
  def change
    # Idempotent: the column may already exist on databases where the original
    # 20260602120000 migration ran before it was renamed to 20260602130000
    # (the rename was forced by a Heroku duplicate-version error). Rails sees
    # this as a fresh migration even though the column is already there.
    add_column :whatsapp_templates, :header_media, :jsonb, if_not_exists: true
  end
end
