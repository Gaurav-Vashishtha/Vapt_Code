class AddVerificationStatusToPreOrderOtps < ActiveRecord::Migration[6.1]
  def change
    add_column :pre_order_otps, :verification_status, :string, default: ''
  end
end
