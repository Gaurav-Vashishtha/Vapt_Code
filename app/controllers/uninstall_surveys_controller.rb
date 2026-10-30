# Public exit survey linked from the uninstall email. No login: the 32-hex
# survey_token on uninstalled_shops identifies the store. /uninstall_survey/preview
# renders the same form with sample data and never saves anything.
class UninstallSurveysController < ActionController::Base
  protect_from_forgery with: :exception
  layout false

  before_action :load_uninstalled

  def show
    @reasons = Churn::ExitSurvey::REASONS
    @likelihood = Churn::ExitSurvey::RETURN_LIKELIHOOD
    @last_response = @preview ? nil : ExitSurveyResponse.where(uninstalled_shop_id: @uninstalled.id).recent_first.first
    @preselected = params[:reason].presence_in(@reasons.keys) || @last_response&.reason || @uninstalled.uninstall_reason
  end

  def create
    unless @preview
      submission = ExitSurveyResponse.create!(
        Churn::ExitSurvey.response_attributes(params).merge(
          uninstalled_shop_id: @uninstalled.id,
          shop_domain: @uninstalled.shop_domain,
          ip_address: request.remote_ip,
          user_agent: request.user_agent.to_s.first(255)
        )
      )
      # Keep the snapshot's reason in step for the churn dashboard (row update only).
      @uninstalled.update_columns(uninstall_reason: submission.reason || @uninstalled.uninstall_reason,
                                  uninstall_feedback: submission.feedback || @uninstalled.uninstall_feedback,
                                  updated_at: Time.current)
      notify_team(submission)
    end
    render :thanks
  end

  private

  def load_uninstalled
    if params[:token] == Churn::ExitSurvey::PREVIEW_TOKEN
      @preview = true
      @uninstalled = Churn::ExitSurvey.preview_shop
    else
      @uninstalled = UninstalledShop.find_by(survey_token: params[:token].to_s)
      head(:not_found) unless @uninstalled
    end
  end

  def notify_team(submission)
    SlackNotifyJob.perform_async(
      ":memo: Exit survey (#{Rails.env}) — #{submission.shop_domain}\n" \
      "Reason: #{submission.reason_label}" \
      "#{submission.wants_callback ? " · wants a call#{" (#{submission.callback_phone})" if submission.callback_phone}" : ''}\n" \
      "#{submission.feedback.to_s.truncate(300)}"
    )
  rescue StandardError
    nil
  end
end
