# frozen_string_literal: true

class OwnerWhatsappAccount < ApplicationRecord
  encrypts :system_user_token

  STATUSES = %w[disabled pending verified].freeze

  def self.current
    first
  end

  def ready_to_send?
    status == "verified" && phone_number_id.present? && system_user_token.present?
  end

  def graph_client
    @graph_client ||= Meta::GraphClient.new(token: system_user_token)
  end
end
