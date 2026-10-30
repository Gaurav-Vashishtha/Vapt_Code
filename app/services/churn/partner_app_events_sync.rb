# frozen_string_literal: true

module Churn
  # Pulls COD King app events (installs, uninstalls, subscription charge
  # activations/cancellations/freezes) from the Partner API into
  # partner_app_events. Idempotent on external_key.
  #
  #   Churn::PartnerAppEventsSync.new(since: 8.days.ago).call  # => rows upserted
  class PartnerAppEventsSync
    CHARGE_FIELDS = 'charge { id name test amount { amount currencyCode } }'

    def initialize(since:, until_time: Time.current, client: PartnerApi::GraphqlClient.new, app_id: nil)
      @since = since
      @until = until_time
      @client = client
      @app_gid = PartnerApi::GraphqlClient.app_gid(app_id)
    end

    def call
      nodes = @client.fetch_all(path: %w[app events]) { |cursor| query(cursor) }
      nodes.count { |node| persist(node) }
    end

    private

    def persist(node)
      domain = node.dig('shop', 'myshopifyDomain').to_s.downcase
      type = node['type'].to_s
      occurred = (Time.zone.parse(node['occurredAt'].to_s) rescue nil)
      return false if domain.blank? || type.blank? || occurred.nil?

      charge = node['charge'] || {}
      key = [type, domain, occurred.utc.iso8601, charge['id']].compact.join('|')

      event = PartnerAppEvent.find_or_initialize_by(external_key: key)
      event.assign_attributes(
        event_type: type,
        shopify_domain: domain,
        shop_gid: node.dig('shop', 'id'),
        occurred_at: occurred,
        charge_id: charge['id'],
        charge_name: charge['name'],
        charge_amount: charge.dig('amount', 'amount'),
        currency: charge.dig('amount', 'currencyCode'),
        charge_test: charge['test'] == true,
        reason: node['reason'],
        description: node['description']
      )
      event.save!
      true
    rescue ActiveRecord::RecordNotUnique
      false
    rescue => e
      Rails.logger.warn("[Churn::PartnerAppEventsSync] persist failed #{domain} #{type}: #{e.class}: #{e.message}")
      false
    end

    def query(after)
      after_clause = after.present? ? %(after: "#{after}") : ''
      <<~GQL
        {
          app(id: "#{@app_gid}") {
            events(
              first: 100
              #{after_clause}
              occurredAtMin: "#{@since.utc.iso8601}"
              occurredAtMax: "#{@until.utc.iso8601}"
              types: [#{PartnerAppEvent::TRACKED_TYPES.join(', ')}]
            ) {
              edges {
                cursor
                node {
                  type
                  occurredAt
                  shop { id myshopifyDomain }
                  ... on RelationshipUninstalled { reason description }
                  ... on SubscriptionChargeActivated { #{CHARGE_FIELDS} }
                  ... on SubscriptionChargeCanceled { #{CHARGE_FIELDS} }
                  ... on SubscriptionChargeFrozen { #{CHARGE_FIELDS} }
                  ... on SubscriptionChargeUnfrozen { #{CHARGE_FIELDS} }
                }
              }
              pageInfo { hasNextPage }
            }
          }
        }
      GQL
    end
  end
end
