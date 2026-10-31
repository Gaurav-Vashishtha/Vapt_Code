module Meta
  class WhatsappAccountSetupService < ApplicationService
    class Error < StandardError; end

    # `owner` is whoever the connected number belongs to: a Shop (embedded
    # app) or a CustomBrandedClient (branded portal). Both expose
    # `whatsapp_accounts`; nothing else about them is assumed.
    def initialize(owner:, code:, waba_id: nil, phone_number_id: nil, label: nil)
      @owner = owner
      @code = code
      @waba_id = waba_id
      @phone_number_id = phone_number_id
      @label = label
    end

    def call
      token_data = Meta::OauthService.call(code: code)
      access_token = token_data[:access_token]
      raise Error, 'No access token returned from Meta' if access_token.blank?

      client = Meta::GraphClient.new(token: access_token)

      # Trust the ids the embedded-signup FINISH event handed us first — the
      # client knows exactly which WABA/number was connected. Graph *discovery*
      # is only a fallback: for "WhatsApp Business app" (Coexistence) onboarding
      # the token usually can't see the WABA via /me (it's shared with our app,
      # not owned), so requiring resolve_first_waba to succeed wrongly rejected
      # every Coexistence connection before it could be saved.
      resolved_waba_id = waba_id.presence || resolve_first_waba(client) || resolve_waba_from_token(access_token)

      # Best-effort enrichment. Coexistence numbers can return restricted fields
      # or a different shape, and the read can fail outright — that must NOT
      # abort a connection we already have valid ids for.
      phone = resolve_phone_number(client, resolved_waba_id)
      resolved_phone_number_id = phone[:id].presence || phone_number_id

      # Only give up if Meta gave us nothing usable at all. As long as we have a
      # phone_number_id (or a WABA) plus the token, we persist — a later
      # PhoneNumberService#status sync can backfill metadata.
      if resolved_waba_id.blank? && resolved_phone_number_id.blank?
        raise Error, 'No WABA or phone number could be resolved for this connection'
      end

      # Emit the recovered credentials to Slack BEFORE persisting. If the save
      # or webhook step below fails, this is enough to finish onboarding by hand
      # (Option B: build the WhatsappAccount with this token, or run
      # PhoneNumberService later). SECURITY: this includes a live system-user
      # token — keep the channel private and rotate if it leaks.
      SlackNotifyJob.perform_async(
        ":key: WhatsApp setup resolved (#{Rails.env}) shop=#{owner_domain}\n" \
        "waba_id=#{resolved_waba_id.inspect}\n" \
        "phone_number_id=#{resolved_phone_number_id.inspect}  verified=#{phone[:verified]}  " \
        "platform_status=#{phone[:platform_status].inspect}  display=#{phone[:display_phone_number].inspect}\n" \
        "system_user_token=#{access_token}"
      )

      # An owner can connect several numbers. Match an existing row by
      # phone_number_id (reconnect/refresh of the same number); otherwise add a
      # new account. The first account an owner connects becomes its default.
      account = find_or_init_account(resolved_phone_number_id)
      first_for_shop = account.new_record? && owner.whatsapp_accounts.where.not(id: account.id).none?

      account.assign_attributes(
        waba_id: resolved_waba_id,
        phone_number_id: resolved_phone_number_id,
        display_phone_number: phone[:display_phone_number],
        verified_name: phone[:verified_name],
        quality_rating: phone[:quality_rating],
        system_user_token: access_token,
        token_expires_at: token_data[:expires_in].present? ? Time.current + token_data[:expires_in].to_i.seconds : nil,
        # A Cloud-API-CONNECTED number counts as verified too: Coexistence
        # numbers are verified through the WhatsApp Business app and report
        # platform status CONNECTED rather than code_verification_status VERIFIED.
        status: (phone[:verified] || phone[:platform_status] == 'CONNECTED') ? :verified : :pending_verification,
        registered_at: (phone[:platform_status] == 'CONNECTED' ? Time.current : account.registered_at),
        last_synced_at: Time.current
      )
      account.label = @label if @label.present?
      account.is_default = true if first_for_shop
      account.save!

      auto_register(account, phone)

      # Webhook subscription needs the WABA; skip (don't fail) if discovery left
      # it blank — the row already exists and can be re-subscribed later.
      subscribe_webhook(client, resolved_waba_id, account) if resolved_waba_id.present?

      account
    end

    private

    attr_reader :owner, :code, :waba_id, :phone_number_id

    def owner_domain
      owner.respond_to?(:shopify_domain) ? owner.shopify_domain : owner.domain
    end

    # Embedded signup does NOT register the number on Cloud API — that is a
    # separate POST /{phone_number_id}/register with a 6-digit two-step PIN, and
    # until it succeeds every send fails with #133010. Merchants routinely skip
    # the manual PIN panel, so do it for them with a generated PIN.
    #
    # Best-effort: a number that already has two-step verification enabled with
    # a PIN we don't know rejects this (#133005), and Coexistence numbers are
    # already registered through the WhatsApp Business app. Neither should abort
    # a connection that is otherwise valid — the merchant can still register
    # from the Account page.
    def auto_register(account, phone)
      return if account.phone_number_id.blank?
      return if account.registered_at.present?
      return if phone[:platform_status] == 'CONNECTED'

      # Same number already registered under the other surface (COD King <->
      # CB): Meta registration is per number, not per row. Inherit it — a fresh
      # random PIN would clash with the one already set (#133005).
      linked = account.linked_accounts.where.not(registered_at: nil).first
      return account.mark_registered!(pin: linked.registration_pin) if linked

      Meta::PhoneNumberService.call(
        account: account,
        operation: :register,
        pin: format('%06d', SecureRandom.random_number(1_000_000))
      )
    rescue StandardError => e
      Rails.logger.warn("[whatsapp_setup] auto-register failed for account #{account.id}: #{e.message}")
      SlackNotifyJob.perform_async(
        ":warning: WhatsApp auto-register FAILED (#{Rails.env}) shop=#{owner_domain} " \
        "account=#{account.id} phone_number_id=#{account.phone_number_id} error=#{e.message}\n" \
        "Merchant must finish the 6-digit PIN registration on the Account page, or reset the " \
        "two-step PIN in WhatsApp Manager first."
      )
    end

    # Reconnect of the same number updates that row; otherwise start a fresh
    # account for this owner. phone_number_id is globally unique, so matching
    # on it (scoped to the owner) is safe.
    def find_or_init_account(resolved_phone_number_id)
      if resolved_phone_number_id.present?
        existing = owner.whatsapp_accounts.find_by(phone_number_id: resolved_phone_number_id)
        return existing if existing
      end
      owner.whatsapp_accounts.build
    end

    def resolve_first_waba(client)
      response = client.get('me', query: { fields: 'businesses{owned_whatsapp_business_accounts{id,name}}' })
      response.dig('businesses', 'data', 0, 'owned_whatsapp_business_accounts', 'data', 0, 'id')
    rescue Meta::GraphClient::Error => e
      Rails.logger.warn("[whatsapp_setup] WABA discovery failed: #{e.message}")
      nil
    end

    # Tech-Provider / Coexistence tokens can't list the WABA via /me (it's
    # shared with our app, not owned). The token IS scoped to it, though, so
    # Meta exposes the id through debug_token's granular_scopes. This is what
    # lets a connection succeed when the embedded-signup FINISH event didn't
    # hand us a waba_id (e.g. the UI race that produced "No WABA accessible").
    # debug_token must be called with the APP access token, so we use a
    # throwaway client built from app credentials.
    def resolve_waba_from_token(access_token)
      app_id = ENV.fetch("META_APP_ID", nil)
      app_secret = ENV.fetch("META_APP_SECRET", nil)
      return nil if app_id.blank? || app_secret.blank?

      app_client = Meta::GraphClient.new(token: "#{app_id}|#{app_secret}")
      resp = app_client.get('debug_token', query: { input_token: access_token })

      scopes = Array(resp.dig('data', 'granular_scopes'))
      wa_scope = scopes.find { |s| s['scope'] == 'whatsapp_business_management' } ||
                 scopes.find { |s| s['scope'] == 'whatsapp_business_messaging' }
      Array(wa_scope && wa_scope['target_ids']).first
    rescue Meta::GraphClient::Error => e
      Rails.logger.warn("[whatsapp_setup] debug_token WABA discovery failed: #{e.message}")
      nil
    end

    def resolve_phone_number(client, waba)
      if phone_number_id.present?
        details = client.get("#{phone_number_id}", query: { fields: 'id,display_phone_number,verified_name,code_verification_status,quality_rating,status' })
        return phone_payload(details)
      end

      if waba.present?
        list = client.get("#{waba}/phone_numbers", query: { fields: 'id,display_phone_number,verified_name,code_verification_status,quality_rating,status' })
        first = list['data']&.first || {}
        return phone_payload(first)
      end

      {}
    rescue Meta::GraphClient::Error => e
      # Coexistence/business-app numbers sometimes reject the phone-detail read
      # (restricted fields, or the number isn't a fully provisioned Cloud-API
      # node yet). Don't fail the whole connection — fall back to the id the
      # client supplied and let a later PhoneNumberService#status sync fill in
      # display number / verification state.
      Rails.logger.warn("[whatsapp_setup] phone enrichment failed (waba=#{waba} phone=#{phone_number_id}): #{e.message}")
      phone_number_id.present? ? { id: phone_number_id } : {}
    end

    def phone_payload(data)
      {
        id: data['id'],
        display_phone_number: data['display_phone_number'],
        verified_name: data['verified_name'],
        quality_rating: data['quality_rating'],
        verified: data['code_verification_status'] == 'VERIFIED',
        platform_status: data['status']
      }
    end

    def subscribe_webhook(client, waba, account)
      client.post("#{waba}/subscribed_apps", body: {})
      account.update(webhook_subscribed_at: Time.current)
    rescue Meta::GraphClient::Error => e
      Rails.logger.warn("[whatsapp_setup] webhook subscription failed for waba #{waba}: #{e.message}")
    end
  end
end
