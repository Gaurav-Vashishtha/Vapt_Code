# frozen_string_literal: true

module CodFormAdmin
  # Base of the COD Form admin JSON API (ARCHITECTURE.md D.14).
  #
  # Authentication is the App Bridge session token, exactly like the other merchant-admin JSON
  # endpoints (F24): AuthenticatedController → ShopifyApp::Authenticated, `@shop` from `set_shop`.
  # JSON in, JSON out, snake_case, no key transformation.
  #
  #   200  the resource, or {"items": [...], "meta": {...}}
  #   402  {"error": "upgrade_required", "feature": "...", "min_tier": "..."}
  #   403  {"error": "module_disabled"}
  #   404  {"error": "not_found"}
  #   422  {"error": "validation_failed", "errors": {"<path>": ["message"]}}
  class BaseController < AuthenticatedController
    class GateError < StandardError
      attr_reader :feature, :min_tier

      def initialize(feature, min_tier)
        @feature = feature
        @min_tier = min_tier
        super("upgrade_required")
      end
    end

    class ValidationError < StandardError
      attr_reader :errors, :code

      def initialize(errors, code: "validation_failed")
        @errors = errors
        @code = code
        super(code)
      end
    end

    PER_PAGE = 50

    # Re-declared so it runs after the session-token callbacks of ShopifyApp::Authenticated
    # (same idiom as PartialRuleSetsController).
    before_action :set_shop
    before_action :require_shop!
    before_action :load_config
    before_action :require_module!
    after_action :publish_saved_changes

    rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from ActiveRecord::RecordNotUnique, with: :render_not_unique
    rescue_from GateError, with: :render_gate_error
    rescue_from ValidationError, with: :render_validation_error

    private

    def require_shop!
      render json: { "error" => "not_found" }, status: :not_found if @shop.nil?
    end

    def load_config
      @config = CodForm::ShopConfig.for(@shop)
    end

    def require_module!
      render json: { "error" => "module_disabled" }, status: :forbidden unless module_enabled?
    end

    # The module is "available to the shop" (NFR-12): per-shop flag or global default.
    # The kill switch does not lock the merchant out of the settings screens.
    def module_enabled?
      @config.module_enabled?
    end

    # ---- request body ---------------------------------------------------------------------------

    # The JSON body as a plain Hash with string keys (never ActionController::Parameters: config
    # payloads have open key sets — locales, text keys — and every value is validated explicitly).
    def body
      @body ||= begin
        data = request.request_parameters
        data = data.to_unsafe_h if data.respond_to?(:to_unsafe_h)
        data.is_a?(Hash) ? data.as_json : {}
      end
    end

    def body_hash(key)
      value = body[key]
      raise ValidationError.new({ key => ["must be an object"] }) unless value.nil? || value.is_a?(Hash)

      value
    end

    # ---- gates ----------------------------------------------------------------------------------

    def gates
      @gates ||= CodForm::Gates.for(@shop, config: @config)
    end

    def gate_allowed?(feature)
      gate = gates[feature.to_s]
      gate.is_a?(Hash) && gate["allowed"] == true
    end

    def gate!(feature)
      return if gate_allowed?(feature)

      gate = gates[feature.to_s]
      raise GateError.new(feature.to_s, gate.is_a?(Hash) ? gate["min_tier"] : nil)
    end

    # ---- validation -----------------------------------------------------------------------------

    # result = a CodFormAdmin::Validators `normalize` result; returns its value or raises.
    def validated!(result)
      raise ValidationError.new(result["errors"]) if result["errors"].any?

      result["value"]
    end

    def invalid!(path, message)
      raise ValidationError.new({ path => [message] })
    end

    # Engine normalisers report [{"path", "code"}] (or strings); the API answers {"<path>": [..]}.
    def engine_errors(list, prefix = nil)
      Array(list).each_with_object({}) do |error, out|
        path, message = error.is_a?(Hash) ? [error["path"], error["code"] || error["message"]] : [nil, error.to_s]
        key = [prefix, path].map(&:to_s).reject(&:empty?).join(".")
        (out[key.empty? ? "base" : key] ||= []) << message.to_s
      end
    end

    def engine_default(name)
      CodForm::Engine::Defaults.public_send(name)
    end

    # ---- writes ---------------------------------------------------------------------------------

    # A save is live right away: the version moves here and the storefront metafield is written
    # once, in this request, after the action has finished (no background job to wait for).
    def bump!
      @config.bump_version!(sync: false)
      @publish_saved_changes = true
    end

    def publish_saved_changes
      publish_storefront! if @publish_saved_changes && response.status < 400
    end

    # Writes the storefront metafield now. Never raises: the caller's save already succeeded.
    def publish_storefront!
      CodForm::MetafieldSyncService.call(@shop, force: true)
    rescue StandardError => e
      Rails.logger.warn("[CodForm] storefront publish failed shop_id=#{@shop.id} #{e.class}")
      { status: :failed }
    end

    def audit(field, old_value, new_value)
      CodForm::MerchantAudit.record(@shop, field, old_value, new_value)
    end

    def audit_changes(prefix, old_hash, new_hash)
      CodForm::MerchantAudit.record_changes(@shop, prefix, old_hash, new_hash)
    end

    def stamp_setup_state(key)
      state = @config.setup_state.is_a?(Hash) ? @config.setup_state : {}
      return if state[key].present?

      @config.update_columns(setup_state: state.merge(key => Time.current.utc.iso8601), updated_at: Time.current)
    end

    # ---- lists ----------------------------------------------------------------------------------

    # => [records of the page, {"page", "pages", "count"}]
    def paginate(scope, per: PER_PAGE)
      page = Validators::Paging.page(params[:page])
      count = scope.count
      [scope.offset((page - 1) * per).limit(per).to_a, Validators::Paging.meta(page: page, per: per, count: count)]
    end

    def iso(time)
      time&.utc&.iso8601
    end

    # {"period","orders","cap","state","behaviour","percent"} (D.15 bootstrap / setup `usage`).
    def usage_summary
      state = CodForm::CapService.state(@shop)
      {
        "period" => state["period"] || CodForm::CapService.period_for(@shop, Time.current),
        "orders" => state["orders"].to_i, "cap" => state["cap"], "state" => state["state"],
        "behaviour" => state["behaviour"], "percent" => state["percent"]
      }
    end

    # ---- error rendering ------------------------------------------------------------------------

    def render_validation_error(error)
      render json: { "error" => error.code, "errors" => error.errors }, status: :unprocessable_entity
    end

    def render_gate_error(error)
      render json: { "error" => "upgrade_required", "feature" => error.feature, "min_tier" => error.min_tier },
             status: :payment_required
    end

    def render_not_found
      render json: { "error" => "not_found" }, status: :not_found
    end

    def render_not_unique
      render json: { "error" => "validation_failed", "errors" => { "base" => ["already exists"] } },
             status: :unprocessable_entity
    end

    def render_record_invalid(error)
      record = error.record
      errors = record.errors.to_hash.each_with_object({}) { |(key, list), out| out[key.to_s] = list }
      if record.respond_to?(:publish_errors) && record.publish_errors.present?
        errors = errors.merge(engine_errors(record.publish_errors, "draft_config"))
      end
      render json: { "error" => "validation_failed", "errors" => errors }, status: :unprocessable_entity
    end
  end
end
