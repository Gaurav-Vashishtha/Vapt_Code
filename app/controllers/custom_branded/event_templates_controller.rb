# frozen_string_literal: true

module CustomBranded
  class EventTemplatesController < BaseController
    def events
      refresh = ActiveModel::Type::Boolean.new.cast(params[:refresh])
      catalog = ParcelxEventCatalog.load(client: @client, refresh: refresh)
      active = @client.custom_branded_template_events.active.includes(:whatsapp_template)
                      .to_h { |m| [m.event_id, { template_id: m.whatsapp_template_id, name: m.whatsapp_template&.name }] }

      render json: {
        events: catalog.events.map { |e| e.merge('active_template' => active[e['event_id']]) },
        source: catalog.source,
        warning: catalog.warning
      }
    rescue ParcelxEventCatalog::Unavailable => e
      render json: { error: "Could not load ParcelX events: #{e.message}" }, status: :bad_gateway
    rescue StandardError => e
      Rails.logger.error("[cb/events] #{e.class}: #{e.message}\n#{e.backtrace&.first(8)&.join("\n")}")
      render json: { error: "Could not load ParcelX events (#{e.class}: #{e.message.to_s.truncate(200)})" }, status: :internal_server_error
    end

    def create
      account = if params[:account_id].present?
                  @client.whatsapp_accounts.find_by(id: params[:account_id])
                else
                  @client.default_whatsapp_account
                end
      return render_error('Connect a WhatsApp number before creating templates.', :not_found) if account.nil?

      template = EventTemplateBuilder.call(client: @client, account: account, attrs: params)
      render json: { template: serialize(template) }, status: :created
    rescue EventTemplateBuilder::Invalid, ::Meta::TemplateService::Error, ActiveRecord::RecordInvalid => e
      render_error(e.message)
    rescue ParcelxEventCatalog::Unavailable => e
      render_error("Could not load ParcelX events: #{e.message}", :bad_gateway)
    end

    def update
      template = find_template
      return render_error('template not found', :not_found) if template.nil?

      mapping = template.custom_branded_template_event
      mapping = EventTemplateMapper.call(client: @client, template: template, attrs: params) if params[:event_id].present?
      return render_error('Map this template to an event first.') if mapping.nil?

      unless params[:active].nil?
        ActiveModel::Type::Boolean.new.cast(params[:active]) ? mapping.activate! : mapping.deactivate!
      end

      render json: { template: serialize(template.reload) }
    rescue EventTemplateMapper::Invalid, ActiveRecord::RecordInvalid => e
      render_error(e.message)
    rescue ActiveRecord::RecordNotUnique
      render_error('Another change to this event was saved at the same time. Please try again.', :conflict)
    rescue ParcelxEventCatalog::Unavailable => e
      render_error("Could not load ParcelX events: #{e.message}", :bad_gateway)
    end

    def destroy
      template = find_template
      return render_error('template not found', :not_found) if template.nil?

      template.custom_branded_template_event&.destroy!
      render json: { template: serialize(template.reload) }
    end

    private

    def find_template
      @client.whatsapp_templates.find_by(id: params[:id])
    end

    def serialize(template)
      {
        id: template.id,
        name: template.name,
        language: template.language,
        category: template.category,
        status: template.status,
        components: template.components,
        account_phone: template.whatsapp_account&.display_phone_number,
        event: EventTemplateSerializer.call(template)
      }
    end

    def render_error(message, status = :unprocessable_entity)
      render json: { error: message }, status: status
    end
  end
end
