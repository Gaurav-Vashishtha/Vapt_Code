# frozen_string_literal: true

module Api
  module V1
    module Cb
      # Template management for a brand — same Meta::TemplateService the
      # portal and embedded app use, so behaviour is identical everywhere.
      class TemplatesController < BaseController
        # GET /api/v1/cb/templates — the brand's templates across all
        # connected numbers, from the local DB (kept fresh by Meta webhooks +
        # sync). Callers pick a template_id from here for POST /messages.
        def index
          templates = client.whatsapp_templates.includes(:whatsapp_account, :custom_branded_template_event).order(:name)
          render json: { templates: templates.map { |t| serialize(t) } }
        end

        # POST /api/v1/cb/templates — submit a new template to Meta for
        # review. Body: { name, language, category, components, header_media? }
        # with components in Meta's own shape (HEADER/BODY/FOOTER/BUTTONS;
        # include example values — Meta review requires them for variables and
        # dynamic URL buttons).
        def create
          account = resolve_account
          return render_error('no WhatsApp account connected for this brand', :not_found) if account.nil?

          template = Meta::TemplateService.call(
            account: account,
            operation: :create,
            attrs: params.to_unsafe_h.slice(:name, :language, :category, :components, :header_media)
          )
          render json: { template: serialize(template) }, status: :created
        rescue Meta::TemplateService::Error => e
          render_error(e.message, :unprocessable_entity)
        end

        # PATCH /api/v1/cb/templates/:id — edit the template's CONTENT on
        # Meta. Body mirrors create: { components, category?, header_media? }.
        # The template returns to `pending` until Meta re-reviews it. Only
        # approved / rejected / paused templates can be edited.
        def update
          template = client.whatsapp_templates.find_by(id: params[:id])
          return render_error('template not found', :not_found) if template.nil?

          unless %w[approved rejected paused].include?(template.status.to_s)
            return render_error(
              "Only approved, rejected, or paused templates can be edited. This one is #{template.status}.",
              :unprocessable_entity
            )
          end

          updated = Meta::TemplateService.call(
            account: template.whatsapp_account,
            operation: :edit,
            template: template,
            attrs: params.to_unsafe_h.slice(:components, :category, :header_media)
          )
          render json: { template: serialize(updated) }
        rescue Meta::TemplateService::Error => e
          render_error(e.message, :unprocessable_entity)
        end

        # POST /api/v1/cb/templates/sync — pull the WABA's templates from Meta
        # into the local DB (statuses included).
        def sync
          account = resolve_account
          return render_error('no WhatsApp account connected for this brand', :not_found) if account.nil?

          templates = Meta::TemplateService.call(account: account, operation: :sync)
          render json: { templates: templates.map { |t| serialize(t) } }
        rescue Meta::TemplateService::Error => e
          render_error(e.message, :unprocessable_entity)
        end

        # DELETE /api/v1/cb/templates/:id — delete on Meta and locally.
        def destroy
          template = client.whatsapp_templates.find_by(id: params[:id])
          return render_error('template not found', :not_found) if template.nil?

          Meta::TemplateService.call(account: template.whatsapp_account, operation: :delete, template: template)
          render json: { ok: true }
        rescue Meta::TemplateService::Error => e
          render_error(e.message, :unprocessable_entity)
        end

        private

        def resolve_account
          if params[:account_id].present?
            client.whatsapp_accounts.find_by(id: params[:account_id])
          else
            client.default_whatsapp_account
          end
        end

        def serialize(t)
          body_text = Array(t.components).find { |c| c.is_a?(Hash) && c['type'].to_s.casecmp?('BODY') }&.dig('text')
          header = Array(t.components).find { |c| c.is_a?(Hash) && c['type'].to_s.casecmp?('HEADER') }
          variable_count = body_text.to_s.scan(/\{\{(\d+)\}\}/).flatten.map(&:to_i).max.to_i
          {
            template_id: t.id,
            name: t.name,
            language: t.language,
            category: t.category,
            status: t.status,
            approved: t.approved?,
            body: body_text,
            header_format: header&.dig('format'),
            variable_count: variable_count,
            components: t.components,
            account_id: t.whatsapp_account_id,
            account_phone: t.whatsapp_account&.display_phone_number,
            rejection_reason: t.rejection_reason,
            event: ::CustomBranded::EventTemplateSerializer.call(t)&.except(:sample_request),
            updated_at: t.updated_at
          }
        end
      end
    end
  end
end
