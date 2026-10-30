class MetaWebhookController < ApplicationController
  skip_before_action :verify_authenticity_token

  def verify
    mode = params['hub.mode']
    token = params['hub.verify_token']
    challenge = params['hub.challenge']

    if mode == 'subscribe' && ActiveSupport::SecurityUtils.secure_compare(token.to_s, ENV['META_WEBHOOK_VERIFY_TOKEN'].to_s)
      render plain: challenge, status: :ok
    else
      render plain: 'Forbidden', status: :forbidden
    end
  end

  def receive
    raw = request.raw_post
    Rails.logger.info("Meta Webhook Payload: #{raw}")
    begin
      data = JSON.parse(raw)

      # Surface onboarding/account webhooks (everything except the high-volume
      # `messages` delivery-status/inbound traffic) to Slack with the COMPLETE
      # payload. When a merchant adds a number this is the clearest record of
      # what Meta returned — the WABA/phone ids here let us finish setup
      # manually if the in-app embedded-signup flow dropped it silently.
      fields = Array(data['entry'])
                 .flat_map { |e| Array(e['changes']).map { |c| c['field'] } }
                 .compact
      if fields.any? { |f| f != 'messages' }
        SlackNotifyJob.perform_async(
          ":satellite_antenna: Meta webhook (#{Rails.env}) fields=#{fields.uniq.inspect}\n" \
          "```#{raw.to_s.truncate(3500)}```"
        )
      end

      Array(data['entry']).each do |entry|
        Array(entry['changes']).each do |change|
          dispatch_change(entry['id'], change['field'], change['value'] || {})
        end
      end

      # Relay to the partner webhook for custom-branded shops. Always via a
      # job (the job itself filters to branded shops and no-ops when the ENV
      # URL is unset) so a slow partner endpoint can never slow this response —
      # Meta disables webhooks that respond slowly.
      if ENV['CB_WEBHOOK_FORWARD_URL'].present?
        Whatsapp::ForwardWebhookJob.perform_async(raw)
      end
    rescue => e
      Rails.logger.error("Failed to process webhook: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    end

    head :ok
  end

  private

  def dispatch_change(waba_id, field, value)
    case field
    when 'message_template_status_update'
      update_template_status(waba_id, value)
    when 'account_review_update'
      update_account_review(waba_id, value)
    when 'phone_number_quality_update', 'phone_number_name_update'
      update_phone_meta(waba_id, value, field)
    when 'messages'
      # Meta uses the `messages` field for BOTH inbound messages and outbound status updates.
      # Status updates land in value['statuses']; inbound messages land in value['messages'].
      # value['metadata']['phone_number_id'] is the receiving number — the
      # unambiguous key we route by when a shop has multiple numbers (possibly
      # sharing a WABA).
      phone_number_id = value.dig('metadata', 'phone_number_id')
      profiles = Array(value['contacts']).select { |c| c.is_a?(Hash) }
                                         .to_h { |c| [c['wa_id'].to_s, c.dig('profile', 'name')] }
      Array(value['statuses']).each { |s| update_message_status(s) }
      Array(value['messages']).each do |m|
        capture_inbound_message(waba_id, phone_number_id, m, m.is_a?(Hash) ? profiles[m['from'].to_s] : nil)
      end
    else
      Rails.logger.info("[meta_webhook] unhandled field=#{field} waba=#{waba_id}")
    end
  end

  def update_template_status(waba_id, value)
    owner = OwnerWhatsappAccount.current
    if owner && waba_id.to_s == owner.waba_id.to_s
      template = OwnerWhatsappTemplate.find_by(name: value['message_template_name'], language: value['message_template_language'])
      template&.update(status: (value['event'] || value['status']).to_s.downcase, updated_at: Time.current)
      return
    end

    # A WABA can now back several account rows (same-WABA multi-number). The
    # template exists in the WABA, so mirror the status onto every account row
    # under it that has a matching template.
    accounts = WhatsappAccount.where(waba_id: waba_id)
    return if accounts.empty?

    template_name = value['message_template_name']
    language      = value['message_template_language']
    new_status    = value['event'] || value['status']
    reason        = value['reason']

    accounts.each do |account|
      template = account.whatsapp_templates.find_by(name: template_name, language: language)
      next unless template

      template.update(
        status: map_template_status(new_status),
        rejection_reason: reason,
        last_synced_at: Time.current
      )
    end
  end

  def update_account_review(waba_id, value)
    decision = value['decision']
    new_status =
      case decision.to_s.upcase
      when 'APPROVED' then :verified
      when 'REJECTED', 'DISAPPROVED' then :disabled
      end
    return unless new_status

    # Account review is WABA-level — apply to every number under the WABA.
    WhatsappAccount.where(waba_id: waba_id).find_each do |account|
      account.update(status: new_status, last_synced_at: Time.current)
    end
  end

  # phone_number_quality_update carries event (FLAGGED/UNFLAGGED/DOWNGRADE/
  # UPGRADE), current_limit and display_phone_number, but no quality value, so
  # the rating itself is re-read by AccountHealthSyncJob.
  def update_phone_meta(waba_id, value, field = nil)
    account = resolve_account(waba_id, value['phone_number_id'], value['display_phone_number'])
    return unless account

    quality_update = field == 'phone_number_quality_update'
    event = value['event'].to_s.upcase.presence

    # A number linked to both COD King and CB has one row per surface — keep
    # them in sync.
    [account, *account.linked_accounts].each do |row|
      attrs = {
        quality_rating: value['current_quality'] || row.quality_rating,
        display_phone_number: value['display_phone_number'] || row.display_phone_number,
        verified_name: value['verified_name'] || row.verified_name,
        last_synced_at: Time.current
      }
      if quality_update
        attrs[:messaging_limit_tier] = value['current_limit'] if value['current_limit'].present?
        attrs[:metadata] = row.metadata.merge('quality_event' => event, 'quality_event_at' => Time.current.iso8601) if event
      end
      row.update(attrs)
    end

    return unless quality_update

    [account, *account.linked_accounts].each do |row|
      Whatsapp::AccountHealthSyncJob.perform_async(row.id)
      Whatsapp::CampaignGuardrails.check_account!(row) if %w[FLAGGED DOWNGRADE].include?(event)
    end
  rescue StandardError => e
    Rails.logger.error("[meta_webhook] phone meta update failed waba=#{waba_id}: #{e.class}: #{e.message}")
  end

  # Resolve the specific account (phone number) a webhook is about. phone_number_id
  # identifies the number; display_phone_number disambiguates within a shared
  # WABA; waba_id is the last-resort fallback for single-number WABAs. A number
  # linked to both COD King and CB has two rows — the shop row wins here so
  # merchant automations keep working (callers with a better signal, e.g. a
  # quoted message, route before falling back to this).
  def resolve_account(waba_id, phone_number_id = nil, display_phone_number = nil)
    if phone_number_id.present?
      account = WhatsappAccount.where(phone_number_id: phone_number_id)
                               .order(Arel.sql('shop_id IS NULL'), :id)
                               .first
      return account if account
    end
    scope = WhatsappAccount.where(waba_id: waba_id)
    if display_phone_number.present?
      match = scope.find_by(display_phone_number: display_phone_number)
      return match if match
    end
    scope.first
  end

  def update_message_status(status)
    meta_id = status['id']
    return if meta_id.blank?

    new_status = status['status']
    at = Time.at(status['timestamp'].to_i) rescue Time.current
    inbox_synced = sync_inbox_status(meta_id, new_status, at, status)

    merchant_log = MerchantWhatsappLog.find_by(meta_message_id: meta_id)
    if merchant_log
      if new_status == 'failed'
        err = Array(status['errors']).first || {}
        merchant_log.update(status: 'failed', failed_at: at, error_code: err['code'], error_message: err['message'] || err['title'])
      else
        merchant_log.advance_status!(new_status, at: at)
      end
    end

    log = WhatsappMessageLog.find_by(meta_message_id: meta_id)
    unless log
      Rails.logger.info("[meta_webhook] status for unknown message id=#{meta_id}") unless inbox_synced
      return
    end

    # Already handed to the retry flow (or given up on): later webhooks for this
    # attempt are duplicates and must not flip the row back to failed.
    return if log.retry_pending? || log.dropped?

    if new_status == 'failed'
      err = Array(status['errors']).first || {}
      log.update(
        error_code: err['code'],
        error_message: err['message'] || err['title']
      )
    end

    log.advance_status!(new_status, at: at)
    if log.whatsapp_campaign_id.present?
      Whatsapp::CampaignStatusUpdater.apply(log, new_status, at)
      guard_campaign_failure(log) if new_status == 'failed'
    end
    handle_reattempt(log, new_status, at)
  end

  def sync_inbox_status(meta_id, new_status, at, status)
    ::Whatsapp::Inbox::StatusSync.apply(meta_id, new_status, at, Array(status['errors']).first)
  rescue StandardError => e
    Rails.logger.error("[meta_webhook] inbox status sync failed id=#{meta_id}: #{e.class}: #{e.message}")
    false
  end

  def guard_campaign_failure(log)
    return unless Whatsapp::CampaignGuardrails::BLOCKING_CODES.include?(log.error_code.to_s[/\d+/].to_s)

    Whatsapp::CampaignGuardrails.on_send_failure(WhatsappCampaign.find_by(id: log.whatsapp_campaign_id), log.error_code)
  rescue StandardError => e
    Rails.logger.error("[meta_webhook] campaign guardrail failed for log #{log.id}: #{e.class}: #{e.message}")
  end

  # Timed retries for messages Meta refused for a retryable reason
  # (BSP_WHATSAPP_RETRY_* env). Never lets a retry problem break the webhook.
  def handle_reattempt(log, new_status, at)
    if new_status == 'failed'
      Whatsapp::ReattemptRecorder.record_bsp_failure(
        log: log, error_code: log.error_code, error_message: log.error_message, at: at
      )
    elsif %w[delivered read].include?(new_status)
      reattempt = WhatsappReattempt.find_by(source_type: 'WhatsappMessageLog', source_id: log.id)
      Whatsapp::ReattemptRecorder.record_delivered(reattempt)
    end
  rescue StandardError => e
    Rails.logger.error("[meta_webhook] reattempt handling failed for log #{log.id}: #{e.class}: #{e.message}")
  end

  def capture_merchant_reply(msg)
    parent_id = msg.dig('context', 'id').to_s
    parent = parent_id.present? ? MerchantWhatsappLog.find_by(meta_message_id: parent_id) : nil
    parent&.advance_status!('replied', at: Time.current)

    text = msg.dig('button', 'text') || msg.dig('text', 'body') ||
           msg.dig('interactive', 'button_reply', 'title') || msg.dig('interactive', 'list_reply', 'title')
    if text.to_s.strip.downcase.in?(%w[stop unsubscribe cancel]) && parent&.shopify_domain.present?
      MerchantWhatsappOptOut.opt_out!(domain: parent.shopify_domain, shop_id: parent.shop_id, phone: msg['from'], reason: 'reply_stop')
    end
  rescue => e
    Rails.logger.warn("[meta_webhook] merchant reply capture failed: #{e.class}: #{e.message}")
  end

  # Stores a customer reply (quick-reply tap, interactive button, or free text)
  # against the originating outbound message log when we can correlate it via
  # context.id. Idempotent on meta_message_id — Meta retries webhooks freely.
  # COD King's own WABA can also hold a shop's number (and in dev the shop is
  # often connected to COD King's own test number), so the WABA alone doesn't
  # say whose message this is; a shop account owning the receiving
  # phone_number_id wins.
  def owner_inbound?(owner, waba_id, phone_number_id)
    return false unless owner && waba_id.to_s == owner.waba_id.to_s
    return true if phone_number_id.blank?

    !WhatsappAccount.where.not(shop_id: nil).exists?(phone_number_id: phone_number_id.to_s)
  end

  def capture_inbound_message(waba_id, phone_number_id, msg, profile_name = nil)
    return unless msg.is_a?(Hash)

    meta_id = msg['id'].to_s
    return if meta_id.blank?

    owner = OwnerWhatsappAccount.current
    return capture_merchant_reply(msg) if owner_inbound?(owner, waba_id, phone_number_id)

    parent_meta_id = msg.dig('context', 'id')
    parent_log = parent_meta_id.present? ? WhatsappMessageLog.find_by(meta_message_id: parent_meta_id) : nil

    # A reply that quotes one of our messages belongs to whoever sent it —
    # this is what splits a number shared by COD King and CB. Otherwise route
    # to the number that received it (phone_number_id).
    account = parent_log&.whatsapp_account
    account = nil if account && phone_number_id.present? && account.phone_number_id.to_s != phone_number_id.to_s
    account ||= resolve_account(waba_id, phone_number_id)
    return Rails.logger.info("[meta_webhook] inbound for unknown waba=#{waba_id} phone_number_id=#{phone_number_id}") unless account
    # The account is owned by a Shop (merchant) OR a CustomBrandedClient
    # (partner API tenant). shop stays nil for client-owned numbers, and the
    # shop-only automations below are skipped for them.
    shop = account.shop
    return Rails.logger.info("[meta_webhook] inbound waba=#{waba_id} has no owner") if shop.nil? && account.custom_branded_client_id.nil?

    type = msg['type'].to_s
    kind, payload, display_text =
      case type
      when 'button'
        # Quick-reply taps on templates land here. `button.payload` is the id
        # we set on the template (often equal to the label); `button.text` is
        # the label shown to the customer.
        [
          'button',
          msg.dig('button', 'payload').to_s.presence || msg.dig('button', 'text').to_s,
          msg.dig('button', 'text').to_s.presence || msg.dig('button', 'payload').to_s
        ]
      when 'interactive'
        # List/button replies sent via interactive (non-template) messages.
        br = msg.dig('interactive', 'button_reply') || msg.dig('interactive', 'list_reply') || {}
        ['interactive', br['id'].to_s, br['title'].to_s.presence || br['id'].to_s]
      when 'text'
        ['text', nil, msg.dig('text', 'body').to_s]
      else
        # image/audio/video/sticker/etc. Stored as 'other' for visibility but
        # without a usable payload.
        ['other', nil, type]
      end

    received_at = Time.at(msg['timestamp'].to_i) rescue Time.current

    inbound = WhatsappInboundMessage.create!(
      shop: shop,
      custom_branded_client_id: account.custom_branded_client_id,
      whatsapp_account: account,
      whatsapp_message_log: parent_log,
      meta_message_id: meta_id,
      parent_meta_message_id: parent_meta_id,
      from_phone: msg['from'].to_s,
      kind: kind,
      payload: payload,
      display_text: display_text,
      received_at: received_at,
      meta_payload: msg
    )

    # Shop-only automations: opt-out keywords, campaign counters, and
    # quick-reply event routing are merchant features. Client-owned numbers
    # (custom branded API) just store the inbound — it reaches the partner via
    # the webhook relay instead.
    if shop
      Whatsapp::OptOutKeywordHandler.maybe_opt_out(shop: shop, from_phone: msg['from'].to_s, text: display_text)
      if parent_log&.whatsapp_campaign_id.present?
        WhatsappCampaign.where(id: parent_log.whatsapp_campaign_id).update_all('replied_count = replied_count + 1')
      end

      # Reserved quick-reply payloads route to specific worker jobs. The
      # registry is the single source of truth for which payload → which event,
      # so adding a new fixed-action event in the registry auto-wires here.
      if %w[button interactive].include?(kind) && payload.present?
        event_key = ::Whatsapp::EventRegistry.event_for_quick_reply_payload(payload)
        case event_key
        when 'cod_verification'
          ::Whatsapp::HandleCodVerificationReplyJob.perform_async(inbound.id)
        end
      end

      record_in_inbox(inbound, account, profile_name)
    end
  rescue ActiveRecord::RecordNotUnique
    # Webhook retry for an already-stored message. Only the inbox copy is
    # retried, in case the first delivery stored the row but not the thread.
    existing = WhatsappInboundMessage.find_by(meta_message_id: meta_id)
    record_in_inbox(existing, existing.whatsapp_account, profile_name) if existing&.shop_id && existing.whatsapp_account
    nil
  rescue => e
    Rails.logger.warn("[meta_webhook] failed to capture inbound id=#{msg['id']}: #{e.class}: #{e.message}")
  end

  def record_in_inbox(inbound, account, profile_name)
    return if account.shop_id.blank?

    ::Whatsapp::Inbox::InboundRecorder.call(inbound, profile_name: profile_name)
  rescue StandardError => e
    Rails.logger.error("[meta_webhook] inbox record failed inbound=#{inbound.id}: #{e.class}: #{e.message}")
  end

  def map_template_status(status)
    case status.to_s.upcase
    when 'APPROVED' then :approved
    when 'REJECTED' then :rejected
    when 'PAUSED'   then :paused
    when 'DISABLED' then :disabled
    else :pending
    end
  end
end
