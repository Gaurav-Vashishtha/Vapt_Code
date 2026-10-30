module Whatsapp
  # Sidekiq wrapper around Meta::SendTemplateMessageService.
  # Retries intentionally NOT configured per product decision — failures are logged
  # to WhatsappMessageLog as :failed and visible in the Logs page.
  class SendTemplateMessageJob < ApplicationJob
    sidekiq_options queue: 'default', retry: false

    def perform(account_id, template_id, recipient, body_parameters, header_parameters, event_type_key, payload_snapshot, button_slug = nil, stage_index = 0, source_external_id = nil, button_index = 0, quick_reply_button_params = nil, url_button_params = nil)
      account = WhatsappAccount.find_by(id: account_id)
      template = WhatsappTemplate.find_by(id: template_id)
      return unless account && template

      ::Meta::SendTemplateMessageService.call(
        account: account,
        template: template,
        recipient: recipient,
        body_parameters: body_parameters,
        header_parameters: header_parameters,
        event_type_key: event_type_key,
        payload_snapshot: payload_snapshot || {},
        button_slug: button_slug,
        stage_index: stage_index,
        source_external_id: source_external_id,
        button_index: button_index,
        quick_reply_button_params: quick_reply_button_params,
        url_button_params: url_button_params
      )
    rescue ::Meta::SendTemplateMessageService::Error => e
      Rails.logger.warn("[whatsapp/send] failed account=#{account_id} template=#{template_id} recipient=#{recipient}: #{e.message}")
      # Swallow — log already marked :failed by the service.
    end
  end
end
