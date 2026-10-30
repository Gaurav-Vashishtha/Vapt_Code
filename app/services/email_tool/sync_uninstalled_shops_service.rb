# frozen_string_literal: true

# Ensures a Shop record exists for each UninstalledShop so email rules can target uninstalled shops.
# New Shop records get created_at from the uninstalled_shop so "X days after installation" rules work.
module EmailTool
  class SyncUninstalledShopsService
    def self.call
      new.call
    end

    def call
      UninstalledShop.find_each do |us|
        ensure_shop_for(us)
      end
    end

    private

    def ensure_shop_for(uninstalled_shop)
      shop = Shop.find_by(shopify_domain: uninstalled_shop.shop_domain)
      if shop
        uninstalled_shop.update_column(:shop_id, shop.id) if uninstalled_shop.shop_id != shop.id
        return
      end

      shop = Shop.new(
        shopify_domain: uninstalled_shop.shop_domain,
        shopify_token: "uninstalled_#{SecureRandom.hex(16)}",
        owner_email: uninstalled_shop.email.presence || "unknown@uninstalled",
        customer_email: uninstalled_shop.email,
        owner_name: uninstalled_shop.owner_name,
        shop_owner: uninstalled_shop.owner_name
      )
      # Use uninstalled_shop.created_at so date rules (e.g. "3 days after installation") work
      shop.created_at = uninstalled_shop.created_at
      shop.updated_at = uninstalled_shop.updated_at
      shop.save!(validate: false)
      uninstalled_shop.update_column(:shop_id, shop.id)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      # Race or duplicate domain, ignore
    end
  end
end
