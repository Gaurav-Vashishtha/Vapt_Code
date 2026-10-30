class AddExcludedCollectionIdsToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :excluded_collection_ids, :string, default:''
    add_column :settings, :selected_collection_ids, :string, default:''
  end
end
