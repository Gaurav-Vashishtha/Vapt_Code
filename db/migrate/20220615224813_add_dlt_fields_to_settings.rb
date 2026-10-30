class AddDltFieldsToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :dlt_template_id, :string
    add_column :settings, :dlt_bulk_template_id, :string
  end
end
