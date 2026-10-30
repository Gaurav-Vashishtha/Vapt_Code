# frozen_string_literal: true

class AddPhoneToReferralPartners < ActiveRecord::Migration[7.0]
  def change
    add_column :referral_partners, :phone, :string
  end
end
