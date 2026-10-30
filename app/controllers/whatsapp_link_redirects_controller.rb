# frozen_string_literal: true

class WhatsappLinkRedirectsController < ActionController::Base
  def show
    data = Whatsapp::ClickTracker.read(params[:token])
    return head :not_found unless data

    Whatsapp::ClickTracker.record!(data) unless bot?
    redirect_to data['u'], allow_other_host: true, status: :found
  end

  private

  # WhatsApp fetches link previews server-side; counting those would inflate clicks.
  def bot?
    request.user_agent.to_s.match?(/WhatsApp|facebookexternalhit|bot|crawler|preview/i) || request.head?
  end
end
