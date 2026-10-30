# frozen_string_literal: true

module Whatsapp
  # Shared template-management actions for the embedded app
  # (Api::Whatsapp::TemplatesController, owner = @shop) and the branded portal
  # (CustomBranded::TemplatesController, owner = @client). Owner access goes
  # through `whatsapp_owner` — defaulting to @shop below; portal controllers
  # override it. Registers `before_action :load_whatsapp_account` so @account
  # is resolved the same way on every surface. Extracted verbatim from the
  # embedded controller so BSP behaviour stays identical.
  module TemplatesActions
    extend ActiveSupport::Concern

    included do
      before_action :load_whatsapp_account
    end

    private

    def whatsapp_owner
      @shop
    end

    public

    def index
      # `all=1` returns the shop's templates across ALL connected numbers
      # (local DB, each tagged with its number) — used by the Notifications
      # page so an event can be routed to a template on any number. Default
      # behaviour lists a single account's templates from Meta.
      if ActiveModel::Type::Boolean.new.cast(params[:all])
        templates = whatsapp_owner.whatsapp_templates.includes(:whatsapp_account).order(:name)
        return render json: { templates: templates.map { |t| serialize_whatsapp_template(t) } }
      end

      templates = Meta::TemplateService.call(account: @account, operation: :list)
      render json: { templates: templates.map { |t| serialize_whatsapp_template(t) } }
    end

    def create
      template = Meta::TemplateService.call(
        account: @account,
        operation: :create,
        attrs: whatsapp_template_params
      )
      render json: { template: serialize_whatsapp_template(template) }, status: :created
    rescue Meta::TemplateService::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # Update the LOCAL binding/variable metadata for a template that already
    # exists on Meta (typically one that was synced down rather than created
    # through this app). Does not touch Meta — just lets the merchant attach
    # event_type_key, variable_mapping, and url_button so the dispatcher and
    # variable resolver can use it.
    def update
      template = @account.whatsapp_templates.find(params[:id])
      raw = params.to_unsafe_h

      # Only update fields the client actually sent. The previous shape
      # (`attrs[:url_button] = attrs[:url_button].presence`) silently nuked
      # `url_button` to nil whenever the PATCH omitted the key — same for
      # `variable_mapping`. The "Change variables" modal only ever sends
      # event_type_key + variable_mapping, so every save through that path
      # was clearing url_button and breaking dynamic URL buttons (Meta then
      # returned 131008 because the button parameter went missing).
      attrs = {}

      if raw.key?('event_type_key')
        attrs[:event_type_key] = raw['event_type_key'].presence
      end

      if raw.key?('variable_mapping')
        # An explicit {} is a real choice (e.g. AUTH templates with no
        # placeholders) — preserve it. Only `nil` is rejected.
        attrs[:variable_mapping] = raw['variable_mapping'] || {}
      end

      if raw.key?('url_button')
        # Explicit `null` / `{}` clears it; absent key leaves the existing
        # config alone.
        attrs[:url_button] = raw['url_button'].presence
      end

      if raw.key?('header_media')
        # Set at bind time from the confirm-mapping modal so synced IMAGE
        # templates (which arrive with no header_media) get a send-usable image
        # source — product image or a fixed URL — instead of falling back to a
        # link Meta can't fetch (131053). Explicit `{}`/null clears it.
        attrs[:header_media] = raw['header_media'].presence || {}
      end

      template.assign_attributes(attrs)
      if template.save
        render json: { template: serialize_whatsapp_template(template) }
      else
        render json: { error: template.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'template not found' }, status: :not_found
    end

    def destroy
      template = @account.whatsapp_templates.find(params[:id])
      Meta::TemplateService.call(account: @account, operation: :delete, template: template)
      render json: { ok: true }
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'template not found' }, status: :not_found
    rescue Meta::TemplateService::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def sync
      templates = Meta::TemplateService.call(account: @account, operation: :sync)
      render json: { templates: templates.map { |t| serialize_whatsapp_template(t) } }
    rescue Meta::TemplateService::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST .../templates/:id/meta_edit
    # Edits the template's content on Meta. Body shape mirrors create:
    # { components, category?, variable_mapping?, url_button?, header_media? }.
    # The template returns to PENDING until Meta re-reviews.
    def meta_edit
      template = @account.whatsapp_templates.find(params[:id])

      unless %w[approved rejected paused].include?(template.status.to_s)
        return render(
          json: { error: "Only approved, rejected, or paused templates can be edited. This one is #{template.status}." },
          status: :unprocessable_entity
        )
      end

      attrs = params.to_unsafe_h.slice(
        :components, :category, :variable_mapping, :url_button, :header_media
      )

      updated = Meta::TemplateService.call(
        account: @account,
        operation: :edit,
        template: template,
        attrs: attrs
      )
      render json: { template: serialize_whatsapp_template(updated) }
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'template not found' }, status: :not_found
    rescue Meta::TemplateService::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    # Templates live under a specific number's WABA. Target the number given by
    # account_id (multi-number); default otherwise so existing calls are
    # unchanged.
    def load_whatsapp_account
      @account = if params[:account_id].present?
                   whatsapp_owner.whatsapp_accounts.find_by(id: params[:account_id])
                 else
                   whatsapp_owner.default_whatsapp_account
                 end
      render(json: { error: 'no WhatsApp account connected' }, status: :not_found) unless @account
    end

    def whatsapp_template_params
      # components have arbitrary nested structure (varies by component type per Meta's spec),
      # so we accept the raw hash here and let TemplateService forward to Meta unchanged.
      params.to_unsafe_h.slice(:name, :language, :category, :components, :event_type_key, :variable_mapping, :url_button, :header_media)
    end

    def serialize_whatsapp_template(t)
      {
        id: t.id,
        meta_template_id: t.meta_template_id,
        name: t.name,
        language: t.language,
        category: t.category,
        whatsapp_account_id: t.whatsapp_account_id,
        account_label: t.whatsapp_account&.display_label,
        account_phone: t.whatsapp_account&.display_phone_number,
        status: t.status,
        components: t.components,
        event_type_key: t.event_type_key,
        variable_mapping: t.variable_mapping,
        url_button: t.url_button,
        header_media: t.header_media,
        rejection_reason: t.rejection_reason,
        bound: t.bound?,
        last_synced_at: t.last_synced_at,
        created_at: t.created_at,
        updated_at: t.updated_at
      }
    end
  end
end
