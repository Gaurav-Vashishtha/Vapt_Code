class AddOtpCampaignCouponToShops < ActiveRecord::Migration[7.2]
  def change
    add_column :shops, :otp_campaign_coupon_code, :string
    add_column :shops, :otp_campaign_coupon_applied_at, :datetime
  end
end
