class AddSkipDraftOrderToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :skip_draft_order, :boolean, default: true
  end
end
