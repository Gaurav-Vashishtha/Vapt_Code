# frozen_string_literal: true

module CustomBranded
  # POST /cb/:shop_domain/templates/:id/test
  # Sends one of the brand's templates to a phone the merchant types in, with
  # sample values for every placeholder — synchronously, so the page can show
  # Meta's verdict right away. Same input contract as POST /api/v1/cb/messages
  # (variables / header_* / button_param), same validation, logged under
  # event_type_key 'custom_branded_test' so it's easy to tell apart from real
  # sends in the panel's stats.
  class TemplateTestsController < BaseController
    TEST_EVENT_KEY = 'custom_branded_test'

    def create
      template = @client.whatsapp_templates.find_by(id: params[:id])
      return render_json_error('template not found', :not_found) unless template

      account = template.whatsapp_account
      return render_json_error('this template is not attached to a connected number', :unprocessable_entity) unless account
      unless account.ready_to_send?
        return render_json_error('The WhatsApp number is not ready to send. Finish registration on this page first.', :unprocessable_entity)
      end
      return render_json_error("Template is #{template.status} on Meta — only approved templates can be sent.", :unprocessable_entity) unless template.approved?

      to = params[:to].to_s.gsub(/\D/, '')
      return render_json_error('Enter the recipient phone number with country code.', :unprocessable_entity) if to.blank?

      send_params = TemplateSendParams.call(template: template, params: params)
      return render_json_error(send_params.detail.presence || send_params.error, :unprocessable_entity) unless send_params.ok?

      log = ::Meta::SendTemplateMessageService.call(
        account: account,
        template: template,
        recipient: to,
        body_parameters: send_params.body_parameters,
        header_parameters: send_params.header_parameters,
        event_type_key: TEST_EVENT_KEY,
        payload_snapshot: { 'test' => true, 'variables' => send_params.raw_variables },
        source_external_id: nil,
        quick_reply_button_params: send_params.quick_reply_button_params,
        url_button_params: send_params.url_button_params
      )

      render json: {
        ok: true,
        log_id: log&.id,
        status: log&.status,
        meta_message_id: log&.meta_message_id,
        to: to,
        template: template.name
      }
    rescue ::Meta::SendTemplateMessageService::Error => e
      render_json_error("Meta rejected the send: #{e.message}", :unprocessable_entity)
    end

    private

    def render_json_error(message, status)
      render json: { error: message }, status: status
    end
  end
end
