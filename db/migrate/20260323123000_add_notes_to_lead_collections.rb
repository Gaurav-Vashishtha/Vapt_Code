class AddNotesToLeadCollections < ActiveRecord::Migration[7.0]
  def change
    add_column :lead_collections, :notes, :text
  end
end
