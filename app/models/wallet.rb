class Wallet < ApplicationRecord
    validates :shopify_domain, presence: true, uniqueness: true
  end