# frozen_string_literal: true

require "uri"
require "csv"

module PartnerApi

  # domains = %w[
  #   sqrm4k-cr.myshopify.com
  #   ddqzm1-ma.myshopify.com
  #   qm0dp0-2p.myshopify.com
  #   e5d7f0-3f.myshopify.com
  #   chamakkattayurveda.myshopify.com
  #   6skfuw-zi.myshopify.com
  #   242795-2.myshopify.com
  #   d09f23-2.myshopify.com
  #   sljewelsinfo.myshopify.com
  #   kpm2i8-1e.myshopify.com
  #   magiclothings.myshopify.com
  #   snehab-com.myshopify.com
  #   kc7srs-x9.myshopify.com
  #   6addp0-bf.myshopify.com
  #   zna5fm-0j.myshopify.com
  #   bansri.myshopify.com
  #   nkzt2a-2c.myshopify.com
  #   h1saxs-fw.myshopify.com
  #   7ry87y-mg.myshopify.com
  #   c4ppt9-bq.myshopify.com
  #   burnlabstore.myshopify.com
  #   petzindia.myshopify.com
  #   tq9pd1-pp.myshopify.com
  #   ccp0md-fs.myshopify.com
  #   alika-fashion-store.myshopify.com
  #   yxs7q5-8b.myshopify.com
  #   geekay-bikes.myshopify.com
  #   isyhtf-i4.myshopify.com
  #   xhfrdi-6f.myshopify.com
  #   0cb1d1-ee.myshopify.com
  #   my-mushroom-world.myshopify.com
  #   w201a2-h0.myshopify.com
  #   ahesas.myshopify.com
  #   amtvpro-official.myshopify.com
  #   sng9sj-s0.myshopify.com
  #   wyggmd-vq.myshopify.com
  #   485684-34.myshopify.com
  #   w07tj1-h0.myshopify.com
  #   rck6xx-0y.myshopify.com
  #   6fmwpq-g3.myshopify.com
  #   i0efhu-h2.myshopify.com
  #   popwheels-india-9pks9.myshopify.com
  #   pfgj10-1m.myshopify.com
  #   29650b.myshopify.com
  #   iw1p33-e2.myshopify.com
  #   040ae1-4.myshopify.com
  #   sxq01f-sy.myshopify.com
  #   pastels-and-pop.myshopify.com
  #   adhuwm-vn.myshopify.com
  #   0bed49-92.myshopify.com
  #   wearevolucion.myshopify.com
  #   x1nh5d-nq.myshopify.com
  #   m6uuz7-pv.myshopify.com
  #   twinklz-by-rebah-5199.myshopify.com
  #   a67ca3-5.myshopify.com
  #   jpwmab-5q.myshopify.com
  #   gplt-dresses.myshopify.com
  #   mt0jwq-v6.myshopify.com
  #   5iccrn-g6.myshopify.com
  #   t1bwvt-ez.myshopify.com
  #   888hga-fa.myshopify.com
  #   wdvdve-fj.myshopify.com
  #   bf8udn-1z.myshopify.com
  #   livevaastu-3717.myshopify.com
  #   wp7w13-fv.myshopify.com
  #   t1bwvt-ez.myshopify.com
  #   w7q9za-cr.myshopify.com
  #   9ubvwt-vg.myshopify.com
  #   95mh4h-de.myshopify.com
  #   0e900t-0k.myshopify.com
  #   innoveda.myshopify.com
  #   bzerss-cm.myshopify.com
  #   blendinfashions.myshopify.com
  #   1v44gt-12.myshopify.com
  #   bahaara-store.myshopify.com
  #   byqc01-x6.myshopify.com
  #   b4660b-4.myshopify.com
  #   bhamadesigns.myshopify.com
  #   1753d5.myshopify.com
  #   d285d2-45.myshopify.com
  #   wottagirl-com.myshopify.com
  #   6fbce2-60.myshopify.com
  #   becute-professional.myshopify.com
  #   xptybq-vm.myshopify.com
  #   sz80fm-5t.myshopify.com
  #   zchzq0-in.myshopify.com
  #   af5904-2.myshopify.com
  #   tpaqz8-hw.myshopify.com
  #   theperfumehub.myshopify.com
  #   mqaimt-vt.myshopify.com
  #   wqsgd0-81.myshopify.com
  #   bqew71-qr.myshopify.com
  #   1crr0d-xh.myshopify.com
  #   wearfamilia.myshopify.com
  #   afiy7w-sq.myshopify.com
  #   kyyxk6-w5.myshopify.com
  #   rnpyc4-11.myshopify.com
  #   1grrya-36.myshopify.com
  #   1d1sj7-xr.myshopify.com
  #   xhfac4-wy.myshopify.com
  #   5nxncc-t0.myshopify.com
  #   e5d7f0-3f.myshopify.com
  #   6dfgu1-zi.myshopify.com
  #   pdmtuq-j6.myshopify.com
  #   c9e313.myshopify.com
  #   160ymw-au.myshopify.com
  #   wydgid-9d.myshopify.com
  #   gxkig1-rs.myshopify.com
  #   44ifd0-wr.myshopify.com
  #   uq1vqe-gc.myshopify.com
  #   i1numd-sk.myshopify.com
  #   5gwrkz-zx.myshopify.com
  #   brumasens.myshopify.com
  #   enablife.myshopify.com
  #   a9afcf-64.myshopify.com
  #   the-chrkha.myshopify.com
  #   awjig1-wp.myshopify.com
  #   78iy0s-a1.myshopify.com
  #   139865-3.myshopify.com
  #   0bnkci-56.myshopify.com
  #   pdmtuq-j6.myshopify.com
  #   aydpk1-ik.myshopify.com
  #   sn06i6-xr.myshopify.com
  #   g1dmkp-n7.myshopify.com
  #   gc-products-by-drandhawa.myshopify.com
  #   4ps1v7-kv.myshopify.com
  #   g30ev0-xk.myshopify.com
  #   461z65-u0.myshopify.com
  #   37cef9-6.myshopify.com
  #   4b1d58-a8.myshopify.com
  #   emigel.myshopify.com
  #   gqf23w-1v.myshopify.com
  #   b1fa0c-gn.myshopify.com
  #   5gmh4a-0n.myshopify.com
  #   118rqb-az.myshopify.com
  #   a0rdc2-t6.myshopify.com
  #   tmgugq-kw.myshopify.com
  #   zz6cuw-3c.myshopify.com
  #   tnqrsj-0r.myshopify.com
  #   n8vcpf-vc.myshopify.com
  #   avbcyb-aj.myshopify.com
  #   fashstorecz.myshopify.com
  #   c00s2z-ts.myshopify.com
  #   4w4cyj-06.myshopify.com
  #   shivansh-art-jewellery.myshopify.com
  #   q3qwim-i7.myshopify.com
  #   vaastraastudio.myshopify.com
  #   0cb1d1-ee.myshopify.com
  #   uaimyr-me.myshopify.com
  #   krx12h-cj.myshopify.com
  #   ]



  # Fetch lifetime earnings (subscription + usage + one-time) for a list of shops
  # using the same Shopify Partner API access used for referral calculations.
  #
  # Env required:
  # - SHOPIFY_PARTNER_ORGANIZATION_ID
  # - SHOPIFY_PARTNER_ACCESS_TOKEN
  #
  # Optional:
  # - SHOPIFY_PARTNER_EARNINGS_START_DATE (YYYY-MM-DD)  default: 2000-01-01
  # - SHOPIFY_PARTNER_APP_ID (filters are not currently applied by the fetcher; kept for future compatibility)
  class LifetimeEarningsService
    def initialize(
      organization_id: ENV.fetch("SHOPIFY_ORGANIZATION_ID", nil),
      access_token: ENV.fetch("SHOPIFY_PARTNER_ACCESS_TOKEN", nil),
      start_date: ENV.fetch("SHOPIFY_PARTNER_EARNINGS_START_DATE", nil),
      end_date: Date.current,
      app_id: ENV.fetch("SHOPIFY_PARTNER_APP_ID", nil)
    )
      @organization_id = organization_id.to_s.strip
      @access_token = access_token.to_s.strip
      @start_date = parse_date(start_date) || Date.new(2000, 1, 1)
      @end_date = end_date.is_a?(Date) ? end_date : Date.parse(end_date.to_s)
      @app_id = app_id.presence

      raise ArgumentError, "SHOPIFY_PARTNER_ORGANIZATION_ID is required" if @organization_id.blank?
      raise ArgumentError, "SHOPIFY_PARTNER_ACCESS_TOKEN is required" if @access_token.blank?

      @fetcher = NetworkServices::ShopifyPartnerRevenueFetcher.new(@access_token, @organization_id)
    end

    # @param shop_domains [Array<String>]
    # @return [Hash] summary + per-shop results
    def call(shop_domains)
      domains = Array(shop_domains).map { |d| normalize_domain(d) }.compact.uniq
      results = []

      domains.each do |domain|
        results << @fetcher.get_lifetime_earnings(
          domain,
          start_date: @start_date,
          end_date: @end_date,
          app_id: @app_id
        )
      end

      successes = results.select { |r| r[:success] }
      total = successes.sum { |r| r.dig(:data, :total_earnings).to_f }.round(2)

      {
        start_date: @start_date,
        end_date: @end_date,
        successful: successes.length,
        failed: results.length - successes.length,
        total_earnings_all_shops: total,
        shops: results
      }
    end

    # Writes a shop-wise distribution CSV.
    # @param shop_domains [Array<String>]
    # @param path [String] absolute or relative file path
    # @return [String] path written
    def write_csv(shop_domains, path:)
      result = call(shop_domains)

      rows = result[:shops].map do |r|
        {
          shop_domain: r[:shop_domain],
          success: r[:success],
          total_earnings: r.dig(:data, :total_earnings),
          currency: r.dig(:data, :currency),
          subscription_revenue: r.dig(:data, :breakdown, :subscription_revenue),
          usage_revenue: r.dig(:data, :breakdown, :usage_revenue),
          one_time_revenue: r.dig(:data, :breakdown, :one_time_revenue),
          total_transactions: r.dig(:data, :total_transactions),
          error: r[:error],
          fetched_at: r[:fetched_at],
        }
      end

      CSV.open(path, "w", write_headers: true, headers: rows.first&.keys || []) do |csv|
        rows.each { |row| csv << row.values }
      end

      path
    end

    private

    def normalize_domain(raw)
      s = raw.to_s.strip
      return nil if s.blank?

      # Strip protocol + path if a full URL is provided
      if s.start_with?("http://", "https://")
        uri = URI.parse(s)
        s = uri.host.to_s
      end

      s = s.downcase.gsub(%r{^/+|/+$}, "")
      s = s.delete_suffix(".myshopify.com") + ".myshopify.com" if s.include?(".myshopify.com")
      s = "#{s}.myshopify.com" unless s.end_with?(".myshopify.com")
      s
    rescue URI::InvalidURIError
      nil
    end

    def parse_date(raw)
      return nil if raw.blank?
      Date.parse(raw.to_s)
    rescue ArgumentError
      nil
    end
  end
end

