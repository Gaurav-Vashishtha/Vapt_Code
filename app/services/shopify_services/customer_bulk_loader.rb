# frozen_string_literal: true

require 'json'
require 'net/http'

module ShopifyServices
  # Loads one finished Shopify bulk export (JSONL, one customer per line) into customers /
  # customer_addresses / customer_shop_mappings at a throttled pace, reading Shopify's file link
  # directly in 8 MB ranges (no staging copy, nothing on disk).
  #
  # Each line goes through the same CustomerSingleDataSaveService the live pull and the
  # customers/create webhook use, so rows end up identical. The byte cursor (bytes_loaded) is saved
  # after every batch; a killed dyno resumes from the last batch and re-saving is idempotent.
  class CustomerBulkLoader
    MAX_SAVE_ATTEMPTS = 3
    CHUNK_BYTES = 8 * 1024 * 1024
    MAX_REDIRECTS = 3

    # Same service, minus its per-customer `puts` (would flood the logs at load speed).
    class QuietSave < ShopifyServices::CustomerSingleDataSaveService
      def puts(*); end
    end

    # keep_going: lambda checked after every batch (window still open, flag still on, lock still ours).
    def initialize(export, deadline:, batch:, pause:, keep_going:)
      @export = export
      @shop = export.shop
      @deadline = deadline
      @batch = batch
      @pause = pause
      @keep_going = keep_going
    end

    # Returns :done, :paused (deadline / window closed) or :closed (Shopify failed or expired it, or it was empty).
    def run
      @export.update!(status: 'loading', load_started_at: @export.load_started_at || Time.current)
      # Fresh link every slice: Shopify's links expire, and this also re-checks the operation's status.
      url = ShopifyServices::CustomerBulkExportService.refresh!(@export)
      return :closed unless @export.status == 'loading'
      raise 'no file url from Shopify' if url.blank?

      loop do
        data, eof = fetch_chunk(url, @export.bytes_loaded)
        return finish! if data.empty? && eof

        part = eof ? data : complete_lines_of(data)
        return :paused if save_part(part) == :paused
        return finish! if eof
      end
    end

    private

    # Reads up to CHUNK_BYTES starting at `offset`. Uses an HTTP Range request; if the server ignores
    # Range (plain 200) the leading bytes are skipped instead. Returns [binary string, reached_end_of_file].
    def fetch_chunk(url, offset, redirects = 0)
      uri = URI.parse(url)
      buffer = String.new(encoding: Encoding::BINARY)
      eof = true
      catch(:chunk_full) do
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 15, read_timeout: 120) do |http|
          req = Net::HTTP::Get.new(uri)
          req['Range'] = "bytes=#{offset}-" if offset.positive?
          http.request(req) do |res|
            case res
            when Net::HTTPRedirection
              raise 'too many redirects fetching bulk file' if redirects >= MAX_REDIRECTS

              return fetch_chunk(res['location'], offset, redirects + 1)
            when Net::HTTPRangeNotSatisfiable
              return [buffer, true] # offset is at/after the end: nothing left
            when Net::HTTPSuccess
              position = res.is_a?(Net::HTTPPartialContent) ? offset : 0
              res.read_body do |piece|
                if position + piece.bytesize > offset
                  skip = [offset - position, 0].max
                  buffer << piece.byteslice(skip, piece.bytesize - skip)
                end
                position += piece.bytesize
                if buffer.bytesize >= CHUNK_BYTES
                  eof = false
                  throw :chunk_full
                end
              end
            else
              raise "bulk file fetch failed: HTTP #{res.code}"
            end
          end
        end
      end
      [buffer, eof]
    end

    # Cut at the last newline so we never split a customer (and never split a UTF-8 character).
    def complete_lines_of(data)
      last = data.rindex("\n".b)
      raise "no line break within #{data.bytesize} bytes" unless last

      data.byteslice(0, last + 1)
    end

    def save_part(part)
      rows = 0
      bytes = 0
      failed = 0
      part.each_line do |line|
        bytes += line.bytesize
        rows += 1
        failed += 1 unless save_line(line)
        next if rows < @batch

        checkpoint(bytes, rows, failed)
        rows = bytes = failed = 0
        return :paused if Time.current >= @deadline || !@keep_going.call

        sleep(@pause) if @pause.positive?
      end
      checkpoint(bytes, rows, failed)
      :ok
    end

    def save_line(line)
      return true if line.strip.empty?

      node = JSON.parse(line.dup.force_encoding(Encoding::UTF_8))
      attempts = 0
      begin
        attempts += 1
        QuietSave.new(nil, @shop, node).call
        true
      rescue StandardError => e
        retry if attempts < MAX_SAVE_ATTEMPTS
        Rails.logger.error("[CustomerBulkLoader] giving up export=#{@export.id} shopify_customer_id=#{node['id']} #{e.class}: #{e.message}")
        false
      end
    rescue JSON::ParserError => e
      Rails.logger.error("[CustomerBulkLoader] bad json export=#{@export.id}: #{e.message}")
      false
    end

    def checkpoint(bytes, rows, failed)
      return if rows.zero? && bytes.zero?

      CustomerBulkExport.where(id: @export.id).update_all(
        ['bytes_loaded = bytes_loaded + ?, rows_loaded = rows_loaded + ?, rows_failed = rows_failed + ?, updated_at = ?',
         bytes, rows, failed, Time.current]
      )
      @export.bytes_loaded += bytes
      @export.rows_loaded += rows
    end

    def finish!
      @export.reload.update!(status: 'loaded', loaded_at: Time.current, error: nil)
      @export.finalize_shop!
      :done
    end
  end
end
