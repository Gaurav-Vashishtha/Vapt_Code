class AddPrepaidHeadingToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :prepaid_heading, :string , default: 'Convert your COD order to Prepaid to get ₹150 off and Faster delivery.'
    add_column :settings, :prepaid_sub_heading, :string , default: 'Pay now to save money and get delivery faster.'
  end
end
