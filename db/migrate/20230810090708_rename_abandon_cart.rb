class RenameAbandonCart < ActiveRecord::Migration[6.0]
  def change
    rename_column :abandoned_carts, :type, :notif_type
  end
end
