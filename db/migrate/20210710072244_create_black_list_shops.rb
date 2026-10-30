class CreateBlackListShops < ActiveRecord::Migration[6.0]
  def change
    create_table :black_list_shops do |t|
      t.string :domain

      t.timestamps
    end
  end
end
