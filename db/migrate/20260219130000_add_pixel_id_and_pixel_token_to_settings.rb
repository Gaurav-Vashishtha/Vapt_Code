# frozen_string_literal: true

class AddPixelIdAndPixelTokenToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :pixel_id, :string
    add_column :settings, :pixel_token, :string
  end
end
