class AddShowOfferAndRewardToSettings < ActiveRecord::Migration[7.0]
  def change
    add_column :settings, :show_offer_and_reward, :boolean, default: true, null: false
  end
end
