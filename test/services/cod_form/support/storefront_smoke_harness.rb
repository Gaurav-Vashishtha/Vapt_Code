# Harness of test/services/cod_form/storefront_api_smoke_test.rb.
#
# Runs the real Api::Form controllers, CodForm services (WS3) and CodForm::Engine classes (WS2)
# on real ActiveSupport + ActionPack, WITHOUT booting the app: ActiveRecord models, Shopify,
# Redis and the other workstreams' AR-backed services are replaced by the in-memory stand-ins
# below. It must never be loaded inside the real Rails process (it defines ::Rails, ::Shop, ...);
# the test file guards against that.
require "active_support/all"
require "action_controller"
require "action_dispatch"
require "logger"
require "stringio"
require "json"
require "securerandom"
require "ostruct"

ROOT = File.expand_path("../../../..", __dir__)
LOG = StringIO.new
Time.zone = "UTC"

module Rails
  class << self
    def cache; @cache ||= ActiveSupport::Cache::MemoryStore.new; end
    def logger; @logger ||= Logger.new(LOG); end
    def env; ActiveSupport::StringInquirer.new("test"); end
    def root; Pathname.new(ROOT); end
    def application
      @app ||= OpenStruct.new(key_generator: ActiveSupport::KeyGenerator.new("x" * 64, iterations: 1), routes: ROUTES)
    end
  end
end

# ---- tiny in-memory ActiveRecord stand-in -------------------------------------------------
class FakeRelation
  include Enumerable
  def initialize(klass, rows); @klass = klass; @rows = rows; end
  def each(&b); @rows.each(&b); end
  def to_a; @rows.dup; end
  def where(*args)
    return NotProxy.new(self) if args.empty?
    cond = args.first
    return FakeRelation.new(@klass, @rows.select { |r| cond.all? { |k, v| FakeRelation.match(r[k], v) } }) if cond.is_a?(Hash)
    self # SQL strings are not interpreted
  end
  def self.match(val, v); v.is_a?(Array) ? v.map(&:to_s).include?(val.to_s) : (v.nil? ? val.nil? : val.to_s == v.to_s); end
  class NotProxy
    def initialize(rel); @rel = rel; end
    def not(cond); FakeRelation.new(nil, @rel.to_a.reject { |r| cond.all? { |k, v| FakeRelation.match(r[k], v) } }); end
  end
  def update_all(arg)
    return @rows.size unless arg.is_a?(Hash)
    @rows.each { |r| arg.each { |k, v| r[k] = v } }
    @rows.size
  end
  def delete_all; @rows.each { |r| @klass.rows.delete(r) }; @rows.size; end
  def first; @rows.first; end
  def count; @rows.size; end
  def exists?; @rows.any?; end
  def pluck(*cols); cols.size == 1 ? @rows.map { |r| r[cols[0]] } : @rows.map { |r| cols.map { |c| r[c] } }; end
  def pick(*cols); pluck(*cols).first; end
  def limit(n); FakeRelation.new(@klass, @rows.first(n)); end
  def order(*); self; end
  def distinct; self; end
  def find_by(cond); where(cond).first; end
  %i[active ordered active_now live running cod_form_mode].each do |scope|
    define_method(scope) do
      fn = (@klass && @klass.scopes[scope]) || ->(rows) { rows }
      FakeRelation.new(@klass, fn.call(@rows))
    end
  end
end

class FakeRecord
  class << self
    def rows; @rows ||= []; end
    def scopes; @scopes ||= {}; end
    def defaults; {}; end
    def all; FakeRelation.new(self, rows); end
    def where(*a); all.where(*a); end
    def find_by(cond); all.where(cond).first; end
    def find(id); find_by(id: id) || raise("not found"); end
    def create!(attrs = {}); r = new(attrs); rows << r; r; end
    def reset!; @rows = []; end
    %i[active ordered active_now live running cod_form_mode].each { |s| define_method(s) { all.send(s) } }
  end
  attr_reader :attrs
  def initialize(attrs = {})
    @attrs = self.class.defaults.deep_dup.merge(attrs.stringify_keys)
    @attrs["id"] ||= self.class.rows.size + 1
    @attrs["created_at"] ||= Time.current
    @attrs["updated_at"] ||= Time.current
  end
  def [](k); @attrs[k.to_s]; end
  def []=(k, v); @attrs[k.to_s] = v; end
  def update_columns(h); h.each { |k, v| @attrs[k.to_s] = v.is_a?(Hash) || v.is_a?(Array) ? JSON.parse(v.to_json) : v }; true; end
  alias update! update_columns
  alias update update_columns
  def reload; self; end
  def attributes; @attrs; end
  def method_missing(name, *args)
    key = name.to_s
    return @attrs[key] if @attrs.key?(key)
    return (@attrs[key.chomp("=")] = args.first) if key.end_with?("=")
    return nil if self.class.defaults.key?(key) || self.class.nullable.include?(key)
    super
  end
  def respond_to_missing?(name, priv = false); @attrs.key?(name.to_s.chomp("=")) || self.class.nullable.include?(name.to_s) || super; end
  def self.nullable; []; end
end

# ---- existing app ---------------------------------------------------------------------------
class Setting < FakeRecord
  def self.defaults
    { "enable_pre_order_otp" => false, "max_retries" => nil, "otp_wait_time" => nil, "pre_whatsapp_button" => false,
      "cod_fee_enabled" => true, "cod_fees" => 500, "is_percentage" => false, "cod_label" => "Utánvét díj",
      "is_tax_included_with_product" => false, "partial_payment_enabled" => false, "store_front_token" => "sf-token",
      "partial_dummy_variant_id" => nil, "verification_tag" => "✅ COD-Verified", "partial_expand_flow_enabled" => false,
      "selected_countries" => "", "show_provinces" => "", "hide_provinces" => "", "selected_zips" => "", "excluded_zips" => "",
      "selected_product_ids" => "", "show_product_ids" => "", "hide_product_variant_ids" => "", "excluded_collection_ids" => "",
      "selected_collection_ids" => "", "hide_vendors" => nil, "show_vendors" => nil, "min_cart_total" => nil, "max_cart_total" => nil,
      "phone_numbers" => "", "email_addresses" => nil, "hide_gift_cards" => false, "locked" => false, "pre_block_phone" => "" }
  end
end
class Shop < FakeRecord
  def self.defaults
    { "shopify_domain" => "brand.myshopify.com", "primary_domain" => "https://brand.hu", "country_code" => "HU", "currency" => "HUF",
      "money_format" => "{{amount_no_decimals_with_space_separator}} Ft", "owner_timezone" => "(GMT+01:00) Europe/Budapest", "charge_id" => nil }
  end
  def self.find_by_shopify_domain_with_cache(domain); find_by(shopify_domain: domain); end
  def setting; @setting ||= Setting.new; end
  def init_session; end
  def partial_rule_sets; FakeRelation.new(nil, []); end
  def abandoned_carts; FakeRelation.new(nil, []); end
end
class Province < FakeRecord; end
class Location < FakeRecord; end
class OrderConfirmation < FakeRecord; end
module Sidekick; module PlanCatalog; def self.tier_for(_shop); "free"; end; end; end
class ScheduledShopReport; def self.extract_iana_from_shop_timezone(_); "Europe/Budapest"; end; end
module CampaignAttributionHelper
  ALLOWED_KEYS = %w[utm_source utm_medium utm_campaign fbclid gclid].freeze
  def self.normalize(raw); (raw || {}).to_h.select { |k, v| ALLOWED_KEYS.include?(k.to_s) && v.to_s.strip != "" }.transform_keys(&:to_s); end
end
module ExchangeRateBank; def self.resolve; [OpenStruct.new(get_rate: 0.9), :static]; end; end
module Rto; class DecisionService; def self.call(**); { status: "Success", band: "low", risk_score: 10 }; end; end; end
module NetworkServices
  class SendPreOrderOtpService; cattr_accessor :result, :calls; self.calls = []
    def self.call(shop_id, params); calls << params; result; end; end
  class VerifyPreOrderOtpService; cattr_accessor :code
    def self.call(shop_id, params); { "verification" => params["otp"] == code, "status" => "success", "sso_session_token" => "SECRET-SSO" }; end; end
end
module ShopifyServices
  class CodOrderCreateService; cattr_accessor :calls, :result; self.calls = []
    def self.call(*args, **kw); calls << [args, kw]; result.respond_to?(:call) ? result.call(kw) : result; end; end
  class OrderTagPostService; cattr_accessor :calls; self.calls = []; def self.call(*a); calls << a; end; end
  class OrderEditAddLineService; cattr_accessor :calls; self.calls = []
    def self.call(shop, **kw); calls << kw; { success: true, order_id: kw[:order_id], total_cents: nil }; end; end
  class PartialDummyVariantCreateService; def self.call(_); "45999"; end; end
end

# ---- other workstreams (AR-backed): fakes with the names of K.9 --------------------------------
module CodForm
  class ShopConfig < FakeRecord
    def self.defaults
      { "storefront_mode" => "cod_form", "module_access" => "on", "general" => {}, "fraud" => {}, "feature_overrides" => {},
        "setup_state" => {}, "allowed_origins" => [], "preview_token" => "a" * 32, "config_version" => 37, "asset_base" => nil }
    end
    def self.scopes; { cod_form_mode: ->(rows) { rows.select(&:cod_form_mode?) } }; end
    def self.for(shop); find_by(shop_id: shop.respond_to?(:id) ? shop.id : shop) || create!(shop_id: shop.id); end
    def cod_form_mode?; storefront_mode == "cod_form"; end
    def module_enabled?; module_access == "on"; end
    def preview_token_matches?(c); c.present? && c.to_s == preview_token; end
  end
  class GlobalSetting < FakeRecord
    def self.defaults; { "kill_switch" => false, "async_orders" => false, "at_cap_behaviour" => "fallback", "grace_orders" => 0, "usage_notice_thresholds" => [80, 100], "settings" => {} }; end
    def self.current; rows.first || create!; end
    def rate_limits; {}; end
  end
  class FeatureGate < FakeRecord
    def to_engine_hash; { "feature_key" => feature_key, "min_tier" => min_tier, "enabled" => enabled }; end
  end
  class PlanLimit < FakeRecord
    def self.defaults; { "plan_tier" => nil, "at_cap_behaviour" => nil, "grace_orders" => nil, "overage_rate" => nil, "active" => true }; end
    def to_engine_hash; attrs.slice("id", "scope_type", "scope_key", "plan_tier", "monthly_cap", "at_cap_behaviour", "grace_orders", "overage_rate", "active"); end
  end
  class CountryGroup < FakeRecord; def self.for_country(_); FakeRelation.new(self, []); end; end
  class OrderUsage < FakeRecord
    def self.defaults; { "orders_count" => 0, "partial_orders_count" => 0, "test_orders_count" => 0 }; end
    def self.for(shop_id, period); find_by(shop_id: shop_id, period: period) || new(shop_id: shop_id, period: period); end
    def self.increment!(shop_id:, period:, column:)
      row = find_by(shop_id: shop_id, period: period) || create!(shop_id: shop_id, period: period)
      row[column] = row[column].to_i + 1
    end
  end
  class Form < FakeRecord
    def self.defaults; { "is_default" => true, "status" => "active", "position" => 0, "targeting" => {}, "published_version" => 1 }; end
    def self.default_for(shop); find_by(shop_id: shop.id, is_default: true) || create!(shop_id: shop.id, published_config: CodForm::Engine::Defaults.form_config); end
  end
  class ShippingRate < FakeRecord
    def self.defaults; { "description" => nil, "currency" => nil, "conditions" => {}, "position" => 0, "active" => true, "source" => "manual" }; end
    def self.scopes; { active: ->(rows) { rows.select(&:active) } }; end
    def to_engine_hash; attrs.slice("id", "name", "description", "price_cents", "currency", "position", "active", "source", "conditions"); end
  end
  class Offer < FakeRecord
    def self.defaults; { "status" => "active", "priority" => 0, "targeting" => { "scope" => "all" }, "config" => {}, "ab_test_id" => nil }; end
    def to_engine_hash; attrs.slice("id", "offer_type", "name", "status", "priority", "targeting", "config", "ab_test_id"); end
  end
  class AbTest < FakeRecord; end
  class BlockEntry < FakeRecord
    def self.normalize(kind, value)
      text = value.to_s.strip
      kind.to_s == "phone" ? text.gsub(/\D/, "").sub(/\A0+/, "") : (kind.to_s == "email" ? text.downcase : text)
    end
  end
  class Rejection < FakeRecord; end
  class Integration < FakeRecord; end
  class Session < FakeRecord
    STATUS_OPEN = "open"; STATUS_OTP_PENDING = "otp_pending"; STATUS_ORDERING = "ordering"; STATUS_ORDERED = "ordered"
    STATUS_HANDOFF_PARTIAL = "handoff_partial"; STATUS_HANDOFF_PREPAID = "handoff_prepaid"; STATUS_BLOCKED = "blocked"
    STATUS_ABANDONED = "abandoned"; STATUS_RECOVERED = "recovered"; STATUS_EXPIRED = "expired"
    ORDERABLE_STATUSES = [STATUS_OPEN, STATUS_OTP_PENDING, STATUS_BLOCKED, STATUS_ABANDONED, STATUS_RECOVERED].freeze
    HANDOFF_STATUSES = [STATUS_HANDOFF_PARTIAL, STATUS_HANDOFF_PREPAID].freeze
    SOURCES = %w[product cart drawer quick_buy api embedded recovery].freeze
    DEVICES = %w[mobile tablet desktop].freeze
    TOKEN_TTL = 2.hours
    def self.defaults
      { "status" => "open", "source" => "product", "is_test" => false, "cart_snapshot" => {}, "quote_snapshot" => {}, "contact" => {},
        "address" => {}, "custom_fields" => {}, "attribution" => {}, "tracking" => {}, "ab_assignments" => {}, "otp" => {}, "risk" => {},
        "upsell" => {}, "order_id" => nil, "order_name" => nil, "order_total_cents" => nil, "order_error" => nil, "otp_verified_at" => nil,
        "phone_normalized" => nil, "email_normalized" => nil, "idempotency_key" => nil, "ordered_at" => nil, "partial_rule_set_id" => nil,
        "cod_form_id" => nil, "client_id" => nil, "device" => nil, "locale" => "en", "currency" => nil, "country_code" => nil, "ip" => nil,
        "user_agent" => nil, "downsell_offer_id" => nil, "recovery_token" => nil }
    end
    def self.scopes; { live: ->(rows) { rows.reject(&:is_test) } }; end
    def initialize(attrs = {}); super; @attrs["public_id"] ||= SecureRandom.uuid; @attrs["expires_at"] ||= Time.current + TOKEN_TTL; end
    def expired?(now = Time.current); expires_at <= now; end
  end
  class FunnelLogger; cattr_accessor :events; self.events = []
    def self.log(**kw); events << kw; true; end; end
  class EventIngestService; cattr_accessor :calls; self.calls = []
    def self.call(**kw); calls << kw; { accepted: kw[:events].size, dropped: 0 }; end; end
  %w[PostOrderJob CapNotifyJob OtpUnavailableNotifyJob MetafieldSyncJob CreateOrderJobStub].each do |name|
    const_set(name, Class.new { cattr_accessor :jobs; self.jobs = []; def self.perform_async(*a); jobs << a; end })
  end
  module Tracking
    class ServerDispatchJob; cattr_accessor :jobs; self.jobs = []; def self.perform_async(*a); jobs << a; end; end
    class PixelResolver; def self.for(_shop, product_ids:, collection_ids:); [{ "platform" => "meta", "pixel_id" => "123", "access_token" => "LEAK", "config" => { "browser" => true, "server" => true, "test_event_code" => "T" }, "targeting" => {} }]; end; end
  end
  module Abandonment; class RecoveryService; def self.prefill(_shop, _token); nil; end; end; end
end
class ApplicationJob; def self.sidekiq_options(*); end; def self.perform_async(*a); new.perform(*a); end; end

require File.join(ROOT, "lib/cod_form_shopify_timeout")
# ---- load the real code under test -------------------------------------------------------------
Dir[File.join(ROOT, "app/services/cod_form/engine/*.rb")].sort.each { |f| require f }
%w[errors cache origin_guard rate_limiter availability gates catalog_service offer_resolver discount_code_service risk_service
   fraud_adapter quote_service tax_service automatic_discount_service cap_service customer_resolver otp_service order_service handoff_service
   upsell_service order_webhook_hook adapters/rules_adapter adapters/cod_fee_adapter adapters/partial_rules_adapter
   adapters/money_format_adapter tracking/event_map].each { |f| require File.join(ROOT, "app/services/cod_form", f) }
require File.join(ROOT, "app/workers/cod_form/create_order_job")
%w[base sessions quotes contacts otp orders handoffs upsells events geo configs].each { |f| require File.join(ROOT, "app/controllers/api/form/#{f}_controller") }

# Shopify Admin GraphQL: one fake entry point.
CATALOG = {
  "44111" => { "price" => "1999.00", "compare" => "2499.00", "qty" => 10, "product" => "8111", "title" => "Widget", "vt" => "Blue" },
  "44123" => { "price" => "999.00", "compare" => nil, "qty" => 5, "product" => "8123", "title" => "Addon", "vt" => "Default Title" }
}
module CodForm
  class CatalogService
    cattr_accessor :queries; self.queries = []
    def self.admin_query(_shop, query, variables = {})
      queries << query[/\b(nodes|shop|codeDiscountNodeByCode|draftOrderCalculate|customers|customerCreate)\b/, 1]
      if query.include?("nodes(ids")
        nodes = variables[:ids].map do |gid|
          id = gid.split("/").last; v = CATALOG[id]
          next nil unless v
          { "__typename" => "ProductVariant", "id" => gid, "title" => v["vt"], "price" => v["price"], "compareAtPrice" => v["compare"],
            "availableForSale" => true, "inventoryQuantity" => v["qty"], "inventoryPolicy" => "DENY", "taxable" => true, "image" => { "url" => "https://cdn/x.png" },
            "contextualPricing" => { "price" => { "amount" => v["price"], "currencyCode" => "HUF" }, "compareAtPrice" => v["compare"] && { "amount" => v["compare"] } },
            "inventoryItem" => { "requiresShipping" => true, "measurement" => { "weight" => { "value" => 0.5, "unit" => "KILOGRAMS" } } },
            "product" => { "id" => "gid://shopify/Product/#{v['product']}", "title" => v["title"], "vendor" => "Acme", "isGiftCard" => false,
                           "featuredImage" => nil, "collections" => { "nodes" => [{ "id" => "gid://shopify/Collection/301" }] } } }
        end
        [{ "nodes" => nodes }, []]
      elsif query.include?("currencyFormats")
        [{ "shop" => { "currencyCode" => "HUF", "taxesIncluded" => true, "currencyFormats" => { "moneyFormat" => "{{amount_no_decimals_with_space_separator}} Ft" } } }, []]
      elsif query.include?("customers(")
        [{ "customers" => { "edges" => [{ "node" => { "id" => "gid://shopify/Customer/77" } }] } }, []]
      else
        [{}, []]
      end
    end
  end
end

ROUTES = ActionDispatch::Routing::RouteSet.new
ROUTES.draw do
  namespace :api do
    namespace :form do
      post 'session',        to: 'sessions#create'
      post 'quote',          to: 'quotes#create'
      post 'contact',        to: 'contacts#create'
      post 'otp/send',       to: 'otp#send_code'
      post 'otp/verify',     to: 'otp#verify'
      post 'orders',         to: 'orders#create'
      post 'orders/status',  to: 'orders#status'
      post 'handoff',        to: 'handoffs#create'
      post 'upsell_accept',  to: 'upsells#accept'
      post 'events',         to: 'events#create'
      get  'config',                     to: 'configs#show'
      get  'geo/:country',               to: 'geo#show',   constraints: { country: /[A-Za-z]{2}/ }
      get  'geo/:country/postal/:code',  to: 'geo#postal', constraints: { country: /[A-Za-z]{2}/, code: /[A-Za-z0-9 \-]{2,12}/ }
    end
  end
end

ORIGIN = "https://brand.hu"
def api(method, path, body = nil, origin: ORIGIN, shop: "brand.myshopify.com", raw: nil)
  url = "/api/form/#{path}#{path.include?('?') ? '&' : '?'}shop=#{shop}"
  env = Rack::MockRequest.env_for(url, method: method, input: raw || (body ? JSON.generate(body) : ""), "CONTENT_TYPE" => "text/plain;charset=UTF-8")
  env["HTTP_ORIGIN"] = origin if origin
  env["REMOTE_ADDR"] = "203.0.113.9"
  status, headers, resp = ROUTES.call(env)
  text = +""; resp.each { |c| text << c }
  [status, (text.empty? ? nil : JSON.parse(text)), headers]
end

def seed!
  [Shop, Setting, CodForm::ShopConfig, CodForm::GlobalSetting, CodForm::FeatureGate, CodForm::PlanLimit, CodForm::OrderUsage, CodForm::Form,
   CodForm::ShippingRate, CodForm::Offer, CodForm::BlockEntry, CodForm::Rejection, CodForm::Session].each(&:reset!)
  Rails.cache.clear
  shop = Shop.create!
  CodForm::ShopConfig.create!(shop_id: shop.id, general: { "countries" => ["HU"] })
  CodForm::Engine::Defaults.feature_gates.each { |g| CodForm::FeatureGate.create!(g) }
  CodForm::PlanLimit.create!(scope_type: "plan", scope_key: "free", monthly_cap: 60, at_cap_behaviour: "grace", grace_orders: 10)
  CodForm::Form.create!(shop_id: shop.id, published_config: CodForm::Engine::Defaults.form_config)
  CodForm::ShippingRate.create!(shop_id: shop.id, name: "Standard delivery", price_cents: 149000, conditions: { "countries" => ["HU"] })
  ShopifyServices::CodOrderCreateService.calls.clear
  ShopifyServices::CodOrderCreateService.result = lambda do |kw|
    { success: true, order_id: 6123456789, order_number: 1042, order_name: "#1042", total_price: "0", currency_code: "HUF",
      order_status_url: "https://brand.hu/orders/abc", draft_total_cents: kw[:form_context][:expected_total_cents], draft_order_id: "gid://shopify/DraftOrder/1" }
  end
  CodForm::FunnelLogger.events.clear
  shop
end
