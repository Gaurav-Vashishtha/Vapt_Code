# frozen_string_literal: true

# COD Form (ARCHITECTURE.md B.10): browser / server pixels per shop and platform.
class CreateTrackingPixels < ActiveRecord::Migration[7.2]
  def change
    create_table :tracking_pixels, if_not_exists: true do |t|
      t.bigint :shop_id, null: false
      t.string :platform, null: false
      t.string :pixel_id, null: false
      t.text :access_token
      t.jsonb :config, null: false, default: {}
      t.jsonb :targeting, null: false, default: {}
      t.boolean :enabled, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps null: false
    end

    add_index :tracking_pixels, %i[shop_id platform enabled],
              name: "index_tracking_pixels_on_shop_id_and_platform_and_enabled", if_not_exists: true
    add_index :tracking_pixels, %i[shop_id platform pixel_id], unique: true,
              name: "index_tracking_pixels_on_shop_id_and_platform_and_pixel_id", if_not_exists: true
  end
end
