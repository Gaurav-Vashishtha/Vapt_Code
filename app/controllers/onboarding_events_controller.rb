class OnboardingEventsController < AuthenticatedController
  # Append-only ingest for onboarding funnel events emitted by the QuickOnboardingV2 wizard.
  # @shop is resolved by AuthenticatedController#set_shop via the embedded session.
  def create
    return render(json: { error: "Shop not found" }, status: :not_found) if @shop.blank?

    event = @shop.onboarding_events.create!(
      event:       params[:event].to_s,
      step:        params[:step].presence,
      feature:     params[:feature].presence || "quick-onboarding-v2",
      metadata:    metadata_hash,
      occurred_at: parsed_occurred_at
    )

    render json: { id: event.id }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue => e
    Rails.logger.error("OnboardingEvents#create: #{e.class} #{e.message}")
    # Analytics must never surface as a user-facing failure; swallow server-side.
    render json: { error: "Could not record event" }, status: :unprocessable_entity
  end

  private

  def metadata_hash
    raw = params[:metadata]
    return {} if raw.blank?
    raw.respond_to?(:permit!) ? raw.permit!.to_h : raw.to_h
  rescue
    {}
  end

  def parsed_occurred_at
    Time.zone.parse(params[:occurred_at].to_s) || Time.current
  rescue
    Time.current
  end
end
