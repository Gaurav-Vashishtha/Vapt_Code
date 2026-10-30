class AddAbandonedToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :abandoned_cart_enabled, :boolean
    add_column :settings, :abandoned_template, :string, :default => 'We notice you left these items in your cart. Complete your checkout now. Check it here {{a_url}}'
  end
end
