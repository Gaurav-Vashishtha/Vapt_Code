# frozen_string_literal: true

module Whatsapp
  # Shared account-management actions for every surface that manages an
  # owner's WhatsApp numbers: the embedded app (Api::Whatsapp::AccountsController,
  # Shopify-authenticated, owner = @shop) and the partner-facing branded portal
  # (CustomBranded::AccountsController, signed-link-authenticated, owner =
  # @client, a CustomBrandedClient). The only assumption is `whatsapp_owner` —
  # defaulting to @shop below; portal controllers override it. Extracted
  # verbatim so BSP behaviour stays identical on both surfaces.
  module AccountsActions
    extend ActiveSupport::Concern

    private

    def whatsapp_owner
      @shop
    end

    def whatsapp_owner_domain
      owner = whatsapp_owner
      owner.respond_to?(:shopify_domain) ? owner.shopify_domain : owner.domain
    end

    public

    # GET .../account (singular) — legacy: the default number's connected-state.
    def show
      account = whatsapp_owner.default_whatsapp_account
      if account
        render json: serialize_whatsapp_account(account)
      else
        render json: { connected: false }
      end
    end

    # GET .../accounts — all connected numbers for the shop.
    def index
      accounts = whatsapp_owner.whatsapp_accounts.order(is_default: :desc, id: :asc)
      render json: { accounts: accounts.map { |a| serialize_whatsapp_account(a) } }
    end

    # POST .../accounts — connect an additional number (or the first).
    def create
      code = params[:code].to_s.strip

      # Capture every add-number callback that reaches the backend — even a
      # malformed one — so a silent drop in the embedded-signup UI is visible.
      # The `code` is single-use, so we log only its presence, never the value.
      SlackNotifyJob.perform_async(
        ":inbox_tray: WhatsApp add-number callback (#{Rails.env}) " \
        "shop=#{whatsapp_owner_domain} code_present=#{code.present?} " \
        "waba_id=#{params[:waba_id].inspect} phone_number_id=#{params[:phone_number_id].inspect}"
      )

      return render(json: { error: 'code is required' }, status: :bad_request) if code.blank?

      account = Meta::WhatsappAccountSetupService.call(
        owner: whatsapp_owner,
        code: code,
        waba_id: params[:waba_id],
        phone_number_id: params[:phone_number_id],
        label: params[:label]
      )

      render json: serialize_whatsapp_account(account), status: :created
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      # e.g. this number is already connected to another shop.
      Rails.logger.warn("[whatsapp/accounts] duplicate/invalid: #{e.message}")
      render json: { error: 'This number is already connected. Disconnect it elsewhere first.' }, status: :unprocessable_entity
    rescue Meta::WhatsappAccountSetupService::Error, Meta::OauthService::Error, Meta::GraphClient::Error => e
      Rails.logger.warn("[whatsapp/accounts] setup failed: #{e.message}")
      SlackNotifyJob.perform_async(
        ":rotating_light: WhatsApp add-number FAILED (#{Rails.env}) " \
        "shop=#{whatsapp_owner_domain} error=#{e.class}: #{e.message}"
      )
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # PATCH .../accounts/:id — rename or set as default.
    def update
      account = whatsapp_owner.whatsapp_accounts.find_by(id: params[:id])
      return render(json: { error: 'account not found' }, status: :not_found) unless account

      account.label = params[:label] if params.key?(:label)
      # Setting default true is honoured; the model unsets the other siblings.
      # We don't allow unsetting the only default directly — pick another one.
      account.is_default = true if ActiveModel::Type::Boolean.new.cast(params[:is_default])

      if account.save
        render json: serialize_whatsapp_account(account)
      else
        render json: { error: account.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    end

    # DELETE .../accounts/:id — disconnect a specific number.
    # DELETE .../account (singular, no id) — legacy: removes default.
    def destroy
      account = if params[:id].present?
                  whatsapp_owner.whatsapp_accounts.find_by(id: params[:id])
                else
                  whatsapp_owner.default_whatsapp_account
                end
      return render(json: { error: 'no account connected' }, status: :not_found) unless account

      account.destroy!
      render json: { connected: whatsapp_owner.whatsapp_accounts.exists? }
    end

    private

    def serialize_whatsapp_account(account)
      {
        connected: true,
        id: account.id,
        label: account.label,
        display_label: account.display_label,
        is_default: account.is_default,
        status: account.status,
        ready_to_send: account.ready_to_send?,
        waba_id: account.waba_id,
        phone_number_id: account.phone_number_id,
        display_phone_number: account.display_phone_number,
        verified_name: account.verified_name,
        quality_rating: account.quality_rating,
        quality_updated_at: account.quality_updated_at,
        messaging_limit_tier: account.messaging_limit_tier,
        messaging_limit: account.messaging_limit,
        webhook_subscribed_at: account.webhook_subscribed_at,
        last_synced_at: account.last_synced_at,
        token_expires_at: account.token_expires_at,
        registered_at: account.registered_at,
        registration_state: account.registration_state,
        registration_error: account.registration_error,
        needs_registration: account.needs_registration?
      }
    end
  end
end
