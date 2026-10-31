# frozen_string_literal: true

module Whatsapp
  # Relays Meta webhook traffic for CUSTOM-BRANDED shops to the partner's
  # webhook URL (ENV['CB_WEBHOOK_FORWARD_URL']). Enqueued by
  # MetaWebhookController#receive AFTER normal processing, so forwarding can
  # never slow Meta's delivery (slow webhook responses get Meta's endpoint
  # disabled).
  #
  # Filtering happens here, not in the controller: each entry/change is
  # resolved via phone_number_id (for `messages`) or waba_id (for
  # account/template events) to its owning WhatsappAccount; only accounts
  # owned by a CustomBrandedClient survive — merchant (Shop) traffic never
  # leaves the app. The forwarded body keeps Meta's own shape (object/entry)
  # so partner code written against Meta's docs Just Works.
  #
  # Headers:
  #   X-CB-Shop-Domain — the client's domain (one request per client when a
  #                      batch spans several)
  #   X-CB-Signature   — sha256=HMAC_SHA256(CB_WEBHOOK_FORWARD_SECRET, body)
  class ForwardWebhookJob < ApplicationJob
    sidekiq_options queue: 'default', retry: 5

    HTTP_TIMEOUT = 5 # seconds — a slow consumer must not back up the queue

    def perform(raw_payload)
      forward_url = ENV.fetch("CB_WEBHOOK_FORWARD_URL", nil).to_s
      return if forward_url.blank?

      data = raw_payload.is_a?(String) ? JSON.parse(raw_payload) : raw_payload
      by_client = partition_entries_by_branded_client(data)
      return if by_client.empty?

      by_client.each do |client, entries|
        payload = { 'object' => data['object'], 'entry' => entries }
        post_to_partner(forward_url, client, payload)
      end
    rescue JSON::ParserError => e
      Rails.logger.warn("[cb_forward] unparseable payload: #{e.message}")
      nil
    end

    private

    # => { client_record => [entry, ...], ... } with entries not owned by a
    # CustomBrandedClient dropped. An entry whose changes span tenants
    # (shared WABA) is split.
    def partition_entries_by_branded_client(data)
      out = Hash.new { |h, k| h[k] = [] }
      client_cache = {}

      Array(data['entry']).each do |entry|
        waba_id = entry['id']
        changes_by_client = Hash.new { |h, k| h[k] = [] }

        Array(entry['changes']).each do |change|
          account = resolve_branded_account(waba_id, change)
          client = account&.custom_branded_client
          next unless client

          change = scope_to_client(change, account)
          next unless change

          client = (client_cache[client.id] ||= client)
          changes_by_client[client] << change
        end

        changes_by_client.each do |client, changes|
          out[client] << entry.merge('changes' => changes)
        end
      end

      out
    end

    # Only accounts owned by a CustomBrandedClient qualify — merchant (Shop)
    # traffic never leaves the app. A number linked to both COD King and CB has
    # two rows, so prefer the client-owned one.
    def resolve_branded_account(waba_id, change)
      phone_number_id = change.dig('value', 'metadata', 'phone_number_id')

      if phone_number_id.present?
        rows = WhatsappAccount.where(phone_number_id: phone_number_id)
        account = rows.client_owned.order(:id).first || rows.order(:id).first
        return account if account
      end

      WhatsappAccount.where(waba_id: waba_id)
                     .order(Arel.sql('custom_branded_client_id IS NULL'), :id)
                     .first
    end

    # Meta sends one stream per number. When the number is shared with a COD
    # King shop, forward only the client's side: statuses of messages the
    # client sent, and inbound messages that quote a client message or quote
    # nothing we sent (plain customer texts). Returns nil when nothing is left.
    def scope_to_client(change, account)
      return change unless change['field'] == 'messages' && account.shared_number?

      value = change['value'] || {}
      client_id = account.custom_branded_client_id

      statuses = Array(value['statuses']).select { |s| log_owner_matches?(s['id'], client_id, unknown: false) }
      messages = Array(value['messages']).select { |m| log_owner_matches?(m.dig('context', 'id'), client_id, unknown: true) }
      return nil if statuses.empty? && messages.empty?

      scoped = value.except('statuses', 'messages')
      scoped['statuses'] = statuses if statuses.any?
      scoped['messages'] = messages if messages.any?
      change.merge('value' => scoped)
    end

    # `unknown` is returned when the message id is blank or not one of our logs.
    def log_owner_matches?(meta_message_id, client_id, unknown:)
      return unknown if meta_message_id.blank?

      row = WhatsappMessageLog.where(meta_message_id: meta_message_id).pick(:id, :custom_branded_client_id)
      return unknown if row.nil?

      row.last == client_id
    end

    def post_to_partner(url, client, payload)
      body = payload.to_json
      headers = {
        'Content-Type' => 'application/json',
        'X-CB-Shop-Domain' => client.domain
      }
      secret = ENV.fetch("CB_WEBHOOK_FORWARD_SECRET", nil).to_s
      if secret.present?
        headers['X-CB-Signature'] = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
      end

      # Each attempt gets its own row (Sidekiq retries included), so the
      # portal's Webhooks section shows the real delivery history.
      delivery = record_delivery(client, payload)

      begin
        response = HTTParty.post(url, body: body, headers: headers, timeout: HTTP_TIMEOUT)
        delivery&.update_columns(response_code: response.code, delivered_at: Time.current)
        return if response.success?

        # Raise so Sidekiq retries with backoff; give up after the retry budget.
        raise "partner webhook returned HTTP #{response.code}"
      rescue StandardError => e
        delivery&.update_columns(error: e.message.to_s.truncate(250)) if delivery&.error.blank?
        Rails.logger.warn("[cb_forward] client=#{client.domain} #{e.class}: #{e.message}")
        raise
      end
    end

    def record_delivery(client, payload)
      fields = Array(payload['entry'])
               .flat_map { |e| Array(e['changes']).map { |c| c['field'] } }
               .compact.uniq.join(',')

      delivery = CustomBrandedWebhookDelivery.create!(
        custom_branded_client_id: client.id,
        fields: fields.presence,
        payload: payload
      )
      CustomBrandedWebhookDelivery.prune!(client.id) if rand < 0.05
      delivery
    rescue StandardError => e
      Rails.logger.warn("[cb_forward] could not record delivery client=#{client.id}: #{e.message}")
      nil
    end
  end
end
