class SmsTemplate < ApplicationRecord
    belongs_to :shop
    enum status: {  requested: "requested", approved: "approved", rejected: "rejected" }
end
