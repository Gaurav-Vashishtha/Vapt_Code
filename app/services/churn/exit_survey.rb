# frozen_string_literal: true

module Churn
  # Exit survey shown from the uninstall email (/uninstall_survey/:token).
  # Every submission is recorded as an ExitSurveyResponse row; the reason and
  # comment are also copied onto the uninstalled_shops snapshot
  # (uninstall_reason / uninstall_feedback) so the churn dashboard shows them.
  module ExitSurvey
    REASONS = {
      'too_expensive' => 'Too expensive',
      'missing_feature' => 'Missing a feature I needed',
      'technical_issues' => 'Technical issues / bugs',
      'hard_to_set_up' => 'Hard to set up or use',
      'switched_app' => 'Switched to another app',
      'not_enough_results' => "Didn't reduce RTO / fake orders enough",
      'closing_store' => 'Closing or pausing my store',
      'temporary' => 'Just testing / will reinstall later',
      'other' => 'Other'
    }.freeze

    RETURN_LIKELIHOOD = {
      'very_likely' => 'Very likely',
      'maybe' => 'Maybe',
      'unlikely' => 'Unlikely'
    }.freeze

    PREVIEW_TOKEN = 'preview'

    module_function

    def reason_label(key)
      REASONS[key.to_s] || key.to_s.humanize.presence
    end

    def preview_shop
      UninstalledShop.new(shop_domain: 'sample-store.myshopify.com', owner_name: 'Sample Store',
                          email: 'owner@example.com')
    end

    # Builds the ExitSurveyResponse attributes from the posted form.
    def response_attributes(params)
      reason = params[:reason].to_s
      reason = nil unless REASONS.key?(reason)
      likelihood = params[:return_likelihood].to_s
      likelihood = nil unless RETURN_LIKELIHOOD.key?(likelihood)
      {
        reason: reason,
        feedback: params[:feedback].to_s.strip.first(5000).presence,
        switched_to: params[:switched_to].to_s.strip.first(120).presence,
        missing_feature: params[:missing_feature].to_s.strip.first(200).presence,
        win_back: params[:win_back].to_s.strip.first(300).presence,
        return_likelihood: likelihood,
        wants_callback: ActiveModel::Type::Boolean.new.cast(params[:wants_callback]) ? true : false,
        callback_phone: params[:callback_phone].to_s.strip.first(30).presence,
        submitted_at: Time.current
      }
    end
  end
end
