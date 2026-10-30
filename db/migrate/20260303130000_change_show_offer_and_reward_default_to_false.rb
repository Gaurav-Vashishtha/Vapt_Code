class ChangeShowOfferAndRewardDefaultToFalse < ActiveRecord::Migration[7.0]
  def up
    change_column_default :settings, :show_offer_and_reward, from: true, to: false
    Setting.where(show_offer_and_reward: true).update_all(show_offer_and_reward: false)
  end

  def down
    change_column_default :settings, :show_offer_and_reward, from: false, to: true
    Setting.where(show_offer_and_reward: false).update_all(show_offer_and_reward: true)
  end
end
