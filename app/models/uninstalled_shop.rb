class UninstalledShop < ApplicationRecord
  belongs_to :shop, optional: true
  has_many :scheduled_emails, dependent: :nullify
  has_many :follow_ups, dependent: :destroy
  has_many :churned_stores, dependent: :nullify
  has_many :exit_survey_responses, dependent: :nullify

  def formatted_created_at
    created_at.strftime("%b %d, %Y at %I:%M %p")
  end
  
  def shop_initials
    return 'NA' if shop_domain.blank?
    
    name_parts = shop_domain.split('.').first.split('-')
    if name_parts.length >= 2
      "#{name_parts[0][0]}#{name_parts[1][0]}".upcase
    else
      shop_domain[0..1].upcase
    end
  end

  def follow_up_target
    shop || Shop.find_by(shopify_domain: shop_domain)
  end

  # Lets the follow-up partial treat an UninstalledShop like a Shop.
  def shopify_domain
    shop_domain
  end
end
