class AddHideGiftCardsToSettings < ActiveRecord::Migration[6.1]
  def change
    add_column :settings, :hide_gift_cards, :boolean, default: false
  end
end