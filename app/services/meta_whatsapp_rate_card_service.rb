# frozen_string_literal: true

require 'httparty'
require 'roo'
require 'cgi'
require 'tempfile'

# Pulls Meta's WhatsApp per-message rate card (INR) and writes our
# whatsapp_utility / whatsapp_marketing price into twilio_pricings.
#
#   Source page : https://developers.facebook.com/docs/whatsapp/pricing/
#   Rate card   : the flat INR card ("Cost per message in INR … effective <date>",
#                 not the volume-tier card) with the latest effective date that
#                 has already started.
#   Buckets     : Meta's own "country calling codes" list on the same page maps
#                 every ISO code to a named market (e.g. Malaysia) or a
#                 "Rest of …" region; anything unlisted is "Other".
#   Our price   : Meta INR rate × MARKUP (2.5) ÷ ₹95 per USD → USD, rounded to
#                 4 dp (twilio_pricings is billed in USD).
#   Skipped     : India and the Philippines (priced separately), and rows we
#                 don't already have.
#
# Fails closed: if the page, card or mapping can't be read sensibly nothing is
# written and the caller gets an error (Slack-notified by the job).
#
#   MetaWhatsappRateCardService.call(dry_run: true)  # preview in rails c
class MetaWhatsappRateCardService
  class Error < StandardError; end

  PRICING_URL = 'https://developers.facebook.com/docs/whatsapp/pricing/'
  CURRENCY = 'INR'
  EXCLUDED_COUNTRIES = %w[IN PH].freeze
  OTHER_MARKET = 'Other'
  MIN_MARKETS = 40       # the card lists ~47 markets
  MIN_NAMED_MAPPINGS = 30
  MIN_REGION_MAPPINGS = 6
  # Facebook serves the full docs page (with the rate-card links) only to a
  # plain browser UA; a bot-style UA gets a 37 KB shell, a full Chrome UA a 400.
  USER_AGENT = 'Mozilla/5.0'

  Change = Struct.new(:country_code, :market, :utility_was, :utility, :marketing_was, :marketing, keyword_init: true)
  Result = Struct.new(:effective_on, :inr_per_usd, :markup, :changes, :unchanged, :skipped, :dry_run, keyword_init: true)

  def self.call(dry_run: false)
    new(dry_run: dry_run).call
  end

  # Fixed ₹95 = $1 for converting the INR card; WHATSAPP_RATE_CARD_INR_PER_USD overrides.
  DEFAULT_INR_PER_USD = 95.0

  def self.inr_per_usd
    value = ENV.fetch("WHATSAPP_RATE_CARD_INR_PER_USD", nil).to_f
    value.positive? ? value : DEFAULT_INR_PER_USD
  end

  def self.markup
    value = ENV.fetch("WHATSAPP_RATE_CARD_MARKUP", nil).to_f
    value.positive? ? value : 2.5
  end

  def initialize(dry_run: false)
    @dry_run = dry_run
  end

  def call
    html = fetch(PRICING_URL).body.to_s
    effective_on, card = load_rate_card(html)
    mapping = market_mapping(html, card.keys)

    raise Error, "INR card has only #{card.size} markets" if card.size < MIN_MARKETS
    raise Error, "#{OTHER_MARKET} market missing from INR card" unless card.key?(OTHER_MARKET)

    inr_per_usd = self.class.inr_per_usd
    raise Error, 'INR per USD rate is not set' unless inr_per_usd.positive?

    markup = self.class.markup
    changes = []
    unchanged = 0
    skipped = []

    TwilioPricing.find_each do |row|
      cc = row.country_code.to_s.strip.upcase
      if cc.blank? || EXCLUDED_COUNTRIES.include?(cc)
        skipped << cc
        next
      end

      market = mapping[cc] || OTHER_MARKET
      rates = card[market] || card[OTHER_MARKET]
      utility = usd(rates[:utility], markup, inr_per_usd)
      marketing = usd(rates[:marketing], markup, inr_per_usd)

      if row.whatsapp_utility.to_f.round(4) == utility && row.whatsapp_marketing.to_f.round(4) == marketing
        unchanged += 1
        next
      end

      changes << Change.new(country_code: cc, market: market,
                            utility_was: row.whatsapp_utility&.to_f, utility: utility,
                            marketing_was: row.whatsapp_marketing&.to_f, marketing: marketing)
      row.update!(whatsapp_utility: utility, whatsapp_marketing: marketing) unless @dry_run
    end

    Result.new(effective_on: effective_on, inr_per_usd: inr_per_usd, markup: markup, changes: changes,
               unchanged: unchanged, skipped: skipped, dry_run: @dry_run)
  end

  private

  def usd(inr_rate, markup, inr_per_usd)
    ((inr_rate.to_f * markup) / inr_per_usd).round(4)
  end

  def fetch(url)
    response = HTTParty.get(url, headers: { 'User-Agent' => USER_AGENT }, follow_redirects: true, timeout: 60)
    raise Error, "GET #{url[0, 80]} → HTTP #{response.code}" unless response.code.to_i == 200

    response
  end

  # ── Rate card ────────────────────────────────────────────────────────────

  # Meta links each card through l.facebook.com with the real CDN URL in `u`.
  # The files are .xlsx even when the URL says .csv.
  def card_urls(html)
    urls = html.scan(%r{https://l\.facebook\.com/l\.php\?u=([^"&\\\s]+)}).flatten.map { |u| CGI.unescape(u) }
    urls += html.scan(%r{https://scontent[^"\\\s]+?\.(?:csv|xlsx)\?[^"\\\s]+}).flatten
    urls.select { |u| u.match?(%r{\.(csv|xlsx)\?}) }
        .uniq { |u| u[%r{/v/[^?]+}] || u }
  end

  def load_rate_card(html)
    today = Date.current
    candidates = []

    card_urls(html).each do |url|
      parsed = parse_card(url)
      next unless parsed

      candidates << parsed
    rescue StandardError => e
      Rails.logger.warn("[MetaWhatsappRateCard] skipped a card: #{e.class}: #{e.message}")
    end

    current = candidates.select { |c| c[:effective_on] <= today }.max_by { |c| c[:effective_on] }
    raise Error, "no current #{CURRENCY} flat rate card found (#{candidates.size} candidates)" unless current

    [current[:effective_on], current[:rates]]
  end

  # Returns { effective_on:, rates: { market => { marketing:, utility: } } } for
  # the flat INR card, nil for any other card (other currency / volume tiers).
  def parse_card(url)
    body = HTTParty.get(url, headers: { 'User-Agent' => USER_AGENT }, timeout: 60).body.to_s
    return nil unless body.start_with?('PK') # xlsx (zip) only

    Tempfile.create(['meta_rate_card', '.xlsx'], binmode: true) do |file|
      file.write(body)
      file.flush
      sheet = Roo::Excelx.new(file.path).sheet(0)

      title = sheet.cell(1, 1).to_s
      match = title.match(/Cost per message in (\w{3}) on the WhatsApp Business Platform, effective (.+?\d{4})/i)
      return nil unless match && match[1].upcase == CURRENCY
      return nil if title.match?(/volume tier/i)

      effective_on = Date.parse(match[2])
      # The header is "Market | Currency | …" ("Marketing rates apply…" above it also starts with "Market").
      header_row = (1..[sheet.last_row.to_i, 40].min).find do |r|
        sheet.cell(r, 1).to_s.strip.casecmp?('Market') && sheet.cell(r, 2).to_s.strip.casecmp?('Currency')
      end
      return nil unless header_row

      headers = (1..sheet.last_column.to_i).to_h { |c| [sheet.cell(header_row, c).to_s.gsub(/\s+/, ' ').strip.downcase, c] }
      currency_col = headers['currency']
      marketing_col = headers['marketing']
      utility_col = headers['utility']
      return nil unless currency_col && marketing_col && utility_col

      rates = {}
      ((header_row + 1)..sheet.last_row.to_i).each do |r|
        market = sheet.cell(r, 1).to_s.strip
        next if market.empty? || sheet.cell(r, currency_col).to_s.strip.upcase != CURRENCY

        marketing = Float(sheet.cell(r, marketing_col), exception: false)
        utility = Float(sheet.cell(r, utility_col), exception: false)
        next unless marketing && utility

        rates[market] = { marketing: marketing, utility: utility }
      end
      { effective_on: effective_on, rates: rates }
    end
  end

  # ── Country → market mapping ─────────────────────────────────────────────

  # Meta lists, under "country calling codes", the named markets and every
  # "Rest of …" region as "Name (CC) - 91" items. Regions are introduced by a
  # heading like "Rest of Asia Pacific – 16 markets". Named markets match a
  # market on the card by name.
  def market_mapping(html, card_markets)
    text = html.gsub('\\"', '"')
    items = text.scan(/"children":\["([^"\]]+)"\]/).flatten.map { |s| s.gsub(/\\+u2013/, '–').strip }

    mapping = {}
    region = nil
    named = 0
    regional = 0
    items.each do |item|
      if (m = item.match(/\A(.+?)\s*[–-]\s*\d+\s+markets?\z/))
        region = card_markets.include?(m[1].strip) ? m[1].strip : nil
        next
      end
      next unless (m = item.match(/\A(.+?) \(([A-Z]{2})\) - \d+\z/))

      name, iso = m[1].strip, m[2]
      next if mapping.key?(iso)

      if card_markets.include?(name)
        mapping[iso] = name
        named += 1
      elsif region
        mapping[iso] = region
        regional += 1
      end
    end

    if named < MIN_NAMED_MAPPINGS || mapping.values.uniq.count { |v| v.start_with?('Rest of') || v == 'North America' } < MIN_REGION_MAPPINGS
      raise Error, "country mapping looks incomplete (named=#{named}, regional=#{regional})"
    end

    mapping
  end
end
