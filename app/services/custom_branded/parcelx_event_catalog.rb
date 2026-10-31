# frozen_string_literal: true

require 'httparty'

module CustomBranded
  class ParcelxEventCatalog
    class Unavailable < StandardError; end

    DEFAULT_URL = 'https://app.parcelx.in/api/v3/communication/registered-event'
    FRESH_TTL = 1.hour
    STALE_TTL = 30.days
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 8

    GROUP_LABELS = {
      'order_updates_events' => 'Order updates',
      'ndr_events' => 'Delivery exceptions (NDR)'
    }.freeze

    SECTION_LABELS = {
      'consignee_details' => 'Customer',
      'order_details' => 'Order',
      'tracking_details' => 'Tracking',
      'seller_details' => 'Seller',
      'channel_details' => 'Sales channel',
      'ndr_reason' => 'NDR'
    }.freeze

    VARIABLE_LABELS = {
      'consignee_details.name' => 'Customer name',
      'consignee_details.mobile' => 'Customer mobile',
      'consignee_details.email' => 'Customer email',
      'consignee_details.address' => 'Delivery address',
      'consignee_details.city' => 'City',
      'consignee_details.state' => 'State',
      'consignee_details.pincode' => 'Pincode',
      'channel_details.order_id' => 'Order ID',
      'channel_details.channel_name' => 'Sales channel',
      'order_details.px_order_id' => 'ParcelX order ID',
      'order_details.order_date' => 'Order date',
      'order_details.order_status' => 'Order status',
      'order_details.payment_mode' => 'Payment mode',
      'order_details.amount.subtotal' => 'Subtotal',
      'order_details.amount.discount' => 'Discount',
      'order_details.amount.total' => 'Order total',
      'order_details.amount.cod_amount' => 'COD amount to pay',
      'order_details.product.0.name' => 'Product name',
      'order_details.product.0.sku' => 'Product SKU',
      'order_details.product.0.quantity' => 'Product quantity',
      'order_details.product.0.price' => 'Product price',
      'order_details.product.0.total' => 'Product total',
      'tracking_details.awb_number' => 'AWB number',
      'tracking_details.courier' => 'Courier',
      'tracking_details.tracking_url' => 'Tracking link',
      'seller_details.name' => 'Store name',
      'seller_details.email' => 'Store email',
      'ndr_reason.ndr_timestamp' => 'NDR time',
      'ndr_reason.ndr_reason' => 'NDR reason',
      'ndr_reason.ndr_remarks' => 'NDR remarks'
    }.freeze

    Result = Struct.new(:events, :source, :warning, keyword_init: true)

    SNAPSHOT_PATH = Rails.root.join('config', 'parcelx_events_snapshot.json')

    def self.load(client: nil, refresh: false)
      new(client).load(refresh: refresh)
    end

    def self.events(client: nil, refresh: false)
      load(client: client, refresh: refresh).events
    end

    def self.find(event_id, client: nil)
      events(client: client).find { |e| e['event_id'] == event_id.to_s }
    end

    def initialize(client = nil)
      @client = client
    end

    def load(refresh: false)
      unless refresh
        cached = Rails.cache.read(cache_key(:fresh))
        return Result.new(events: cached, source: 'cache') if cached.present?
      end

      fetched = live_events

      Rails.cache.write(cache_key(:fresh), fetched, expires_in: FRESH_TTL)
      Rails.cache.write(cache_key(:stale), fetched, expires_in: STALE_TTL)
      Result.new(events: fetched, source: 'live')
    rescue Unavailable => e
      Rails.logger.warn("[cb/parcelx_events] live fetch failed: #{e.message}")
      fallback(e.message)
    end

    private

    def access_token
      @client&.metadata.to_h['parcelx_access_token'].presence || ENV.fetch("PARCELX_ACCESS_TOKEN", nil).to_s
    end

    def endpoint
      ENV.fetch("PARCELX_EVENTS_URL", nil).presence || DEFAULT_URL
    end

    def cache_key(kind)
      "cb/parcelx_events/v1/#{Digest::SHA256.hexdigest("#{endpoint}|#{access_token}")[0, 16]}/#{kind}"
    end

    def fallback(reason)
      stale = Rails.cache.read(cache_key(:stale))
      if stale.present?
        return Result.new(events: stale, source: 'stale',
                          warning: "Showing the last list we got from ParcelX. Live refresh failed: #{reason}")
      end

      snapshot = normalize(JSON.parse(File.read(SNAPSHOT_PATH)))
      raise Unavailable, reason if snapshot.empty?

      Result.new(events: snapshot, source: 'snapshot',
                 warning: "Showing the standard ParcelX event list. Live refresh failed: #{reason}")
    rescue Errno::ENOENT, JSON::ParserError
      raise Unavailable, reason
    end

    # Anything the HTTP stack or an unexpected payload shape throws has to end in the fallback
    # list, never in a 500 on the merchant's builder.
    def live_events
      events = normalize(fetch)
      raise Unavailable, 'ParcelX returned no events' if events.empty?

      events
    rescue Unavailable
      raise
    rescue StandardError => e
      Rails.logger.error("[cb/parcelx_events] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      raise Unavailable, "#{e.class}: #{e.message.to_s.truncate(200)}"
    end

    def fetch
      raise Unavailable, 'PARCELX_ACCESS_TOKEN is not set on the server' if access_token.blank?

      response = HTTParty.post(
        endpoint,
        headers: { 'access-token' => access_token, 'Accept' => 'application/json' },
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT
      )
      unless response.success?
        raise Unavailable, "ParcelX answered HTTP #{response.code}: #{response.body.to_s.truncate(200)}"
      end

      body = response.parsed_response
      body = JSON.parse(body) if body.is_a?(String)
      raise Unavailable, 'ParcelX returned an unexpected response' unless body.is_a?(Hash)
      raise Unavailable, body['message'].presence || 'ParcelX returned an error' unless body['status']

      body['data'].is_a?(Hash) ? body['data'] : {}
    end

    def normalize(data)
      data.flat_map do |group_key, list|
        next [] unless list.is_a?(Array)

        list.filter_map do |raw|
          next unless raw.is_a?(Hash) && raw['event_id'].present?

          {
            'event_id' => raw['event_id'].to_s,
            'event_name' => raw['event_name'].to_s.strip,
            'group' => group_key.to_s,
            'group_label' => GROUP_LABELS[group_key.to_s] || group_key.to_s.humanize,
            'variables' => variables_for(raw['payload'])
          }
        end
      end
    end

    def variables_for(payload)
      leaves = []
      walk(payload, [], leaves)
      leaves.map do |path, sample|
        key = path.join('.')
        {
          'key' => key,
          'label' => VARIABLE_LABELS[key] || derived_label(path),
          'section' => SECTION_LABELS[path.first] || path.first.to_s.humanize,
          'sample' => sample.to_s
        }
      end
    end

    # Arrays (order_details.product) are exposed through their first element only:
    # a WhatsApp template has a fixed number of placeholders, so "every product" can't be a variable.
    def walk(node, path, out)
      case node
      when Hash then node.each { |k, v| walk(v, path + [k.to_s], out) }
      when Array then walk(node.first, path + ['0'], out) unless node.empty?
      else out << [path, node] unless path.empty?
      end
    end

    def derived_label(path)
      words = path.reject { |seg| seg.match?(/\A\d+\z/) }
      parent = words[-2].to_s.sub(/_details\z/, '').humanize
      leaf = words.last.to_s.humanize.downcase
      parent.present? ? "#{parent} #{leaf}" : leaf.capitalize
    end
  end
end
