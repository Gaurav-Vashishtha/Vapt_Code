# frozen_string_literal: true

class AddPromoBannerSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :promo_banner_show, :boolean, default: true
    add_column :settings, :promo_banner_text, :string, default: ""
    add_column :settings, :promo_banner_color, :string, default: ""
  end
end
