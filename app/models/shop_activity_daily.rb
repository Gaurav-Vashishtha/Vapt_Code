class ShopActivityDaily < ApplicationRecord
  self.table_name = 'shop_activity_dailies'

  belongs_to :shop, optional: true

  scope :for_shop, ->(shop_id) { where(shop_id: shop_id) }
  scope :between, ->(from, to) { where(activity_date: from..to) }
end
