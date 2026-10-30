# frozen_string_literal: true

class AddPromoTextColorToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :promo_text_color, :string, default: ""
  end
end
