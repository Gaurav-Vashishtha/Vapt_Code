# frozen_string_literal: true

class CallTarget < ApplicationRecord
  SEGMENTS = %w[new_install active churned].freeze
  STATUSES = %w[pending attempted skipped rolled_over].freeze

  SEGMENT_LABELS = {
    "new_install" => "New install",
    "active" => "Active",
    "churned" => "Churned"
  }.freeze

  scope :for_date, ->(date) { where(call_date: date) }
  scope :ranked, -> { order(:rank) }
  scope :pending, -> { where(status: "pending") }
  scope :attempted, -> { where(status: "attempted") }

  def segment_label
    SEGMENT_LABELS.fetch(segment, segment)
  end

  def reason_list
    Array(reasons)
  end

  def shop
    return @shop if defined?(@shop)
    @shop = shop_id ? Shop.find_by(id: shop_id) : nil
  end

  def uninstalled_shop
    return @uninstalled_shop if defined?(@uninstalled_shop)
    @uninstalled_shop = segment == "churned" ? UninstalledShop.where(shop_domain: shopify_domain).order(created_at: :desc).first : nil
  end

  def contact_phone
    segment == "churned" ? uninstalled_shop&.phone : shop&.owner_phone
  end

  def contact_name
    if segment == "churned"
      uninstalled_shop&.owner_name
    else
      shop&.owner_name.presence || shop&.shop_owner
    end
  end

  def contact_email
    segment == "churned" ? uninstalled_shop&.email : shop&.owner_email
  end

  def admin_path
    if segment == "churned"
      uninstalled_shop ? "/admin/uninstalled_shops/#{uninstalled_shop.id}" : nil
    else
      shop_id ? "/admin/shops/#{shop_id}" : nil
    end
  end

  def crisp_url
    return shop.crisp_url if segment != "churned" && shop.respond_to?(:crisp_url) && shop&.crisp_url.present?

    website_id = ENV.fetch("CRISP_WEBSITE_ID", nil)
    return nil if website_id.blank? || contact_email.blank?

    "https://go.crisp.chat/chat/embed/?website_id=#{website_id}&user_email=#{CGI.escape(contact_email)}"
  end
end
