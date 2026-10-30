# app/controllers/unsubscribe_controller.rb
class UnsubscribeController < ApplicationController
    def create
      email = params[:email]
      source = params[:source] || "general"
  
      if email.blank?
        return render plain: "Invalid unsubscribe link", status: :bad_request
      end

      normalized = email.to_s.downcase.strip
      record = UnsubscribedEmail.for_email(normalized).first || UnsubscribedEmail.new(email: normalized)
      record.source = source
      record.unsubscribed_at = Time.current
      record.save!

      render plain: "You have been unsubscribed successfully."
    end
  end
  