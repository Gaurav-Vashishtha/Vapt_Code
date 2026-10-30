# frozen_string_literal: true

class WhatsappGuardrailMailer < ApplicationMailer
  layout 'mailer'

  REASONS = %w[quality_low failure_spike account_blocked].freeze

  def campaign_paused(campaign_id)
    @campaign = WhatsappCampaign.find_by(id: campaign_id)
    return if @campaign.nil?

    @shop = @campaign.shop
    return if @shop.nil? || @shop.owner_email.blank?

    @reason = REASONS.include?(@campaign.pause_reason) ? @campaign.pause_reason : 'quality_low'
    @owner = @shop.owner_name.presence || I18n.t('whatsapp_guardrail_mailer.common.there', default: 'there')
    @campaign_name = @campaign.name
    @number = @campaign.whatsapp_account&.display_label
    @admin_url = "https://#{@shop.shopify_domain}/admin/apps"

    mail(to: @shop.owner_email, subject: copy("subject_#{@reason}", name: @campaign_name))
  end

  helper_method :copy

  private

  DEFAULTS = {
    'subject_quality_low' => 'Your WhatsApp campaign "%{name}" was paused: number quality is low',
    'subject_failure_spike' => 'Your WhatsApp campaign "%{name}" was paused: too many messages were blocked',
    'subject_account_blocked' => 'Your WhatsApp campaign "%{name}" was paused: WhatsApp blocked sending',
    'greeting' => 'Hi %{name},',
    'body_quality_low' => 'We paused "%{name}" because WhatsApp rated the quality of your number %{number} as low. Sending more messages now could get your number restricted.',
    'body_failure_spike' => 'We paused "%{name}" because WhatsApp blocked many of its messages in the last 30 minutes for sending too fast or too often. Continuing could get your number restricted.',
    'body_account_blocked' => 'We paused "%{name}" because WhatsApp stopped messages from your number %{number}. This usually means the account is locked, has a payment problem or needs to be registered again.',
    'what_to_do_quality_low' => 'Wait for your number quality to improve before resuming. Messages that are relevant and expected by customers help it recover.',
    'what_to_do_failure_spike' => 'Wait a few hours before resuming, and consider sending to a smaller, more engaged audience.',
    'what_to_do_account_blocked' => 'Check your WhatsApp Business Account in Meta Business Manager, fix the issue, then resume the campaign.',
    'resume_note' => 'Nobody who already got the message will get it again. The campaign stays paused until you resume it.',
    'open_app' => 'Open COD King in your Shopify admin',
    'sign_off_html' => 'Thanks,<br/>The COD King team'
  }.freeze

  def copy(key, **vars)
    I18n.t("whatsapp_guardrail_mailer.campaign_paused.#{key}", default: DEFAULTS.fetch(key), **vars)
  end
end
