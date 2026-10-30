# frozen_string_literal: true

module CodFormAdmin
  # Form designer (D.15, C.2): forms CRUD with draft / publish (FRM-11) and targeting (FRM-22).
  # The storefront reads only `published_config`; PUT never touches it.
  class FormsController < BaseController
    COUNTRIES_PATH = "config/cod_form/countries.json"
    COUNTRY_NAMES = {
      "IN" => "India", "PK" => "Pakistan", "MA" => "Morocco", "CO" => "Colombia", "PE" => "Peru",
      "DO" => "Dominican Republic", "HU" => "Hungary", "RS" => "Serbia", "AE" => "United Arab Emirates",
      "SA" => "Saudi Arabia", "EG" => "Egypt", "ID" => "Indonesia", "PH" => "Philippines", "MX" => "Mexico",
      "TR" => "Türkiye", "RO" => "Romania", "PL" => "Poland", "ES" => "Spain", "IT" => "Italy",
      "PT" => "Portugal", "FR" => "France", "DE" => "Germany", "GB" => "United Kingdom", "US" => "United States"
    }.freeze

    before_action :load_form, only: %i[show update publish discard_draft duplicate make_default destroy]

    def index
      render json: { "items" => list_items }
    end

    # GET /cod_form/forms/defaults
    def defaults
      render json: {
        "config" => engine_default(:form_config),
        "templates" => engine_default(:templates),
        "texts" => CodForm::EnableService.default_texts,
        "countries" => countries
      }
    end

    def show
      render json: form_json(@form)
    end

    # POST /cod_form/forms  {"name", "template_key", "targeting"}
    # The first form of a shop is its default form; every further form needs `multiple_forms`
    # (1 form without the gate, 5 with it — PM "Limits").
    def create
      CodForm::Form.default_for(@shop)
      ensure_room_for_another_form!

      errors = Validators::Util.errors
      name = Validators::Util.string(body["name"], "name", errors, "", max: 120, required: true)
      targeting = Validators::Targeting.normalize(body["targeting"], "targeting", errors, with_scope: false)
      template_key = body["template_key"].presence
      config = engine_default(:new_form_config) # Express theme unless a template sets the design
      if template_key
        gate!("templates")
        template = engine_default(:templates).find { |entry| entry["key"] == template_key }
        errors["template_key"] << "unknown template" if template.nil?
        config = Validators::FormDraft.apply_template(config, template) if template
      end
      clean = errors.reject { |_, list| list.empty? }
      raise ValidationError.new(clean) if clean.any?

      config = CodForm::Engine::FormConfig.normalize(config)["config"]
      form = CodForm::Form.create!(
        shop_id: @shop.id, name: name, is_default: false, status: CodForm::Form::STATUS_ACTIVE,
        position: (scope.maximum(:position) || 0) + 1, targeting: targeting, template_key: template_key,
        draft_config: config, published_config: config, published_version: 1, published_at: Time.current
      )
      audit("form.#{form.id}.created", "", form.name)
      bump!
      render json: form_json(form), status: :created
    end

    # PUT /cod_form/forms/:id  {"name", "targeting", "draft_config"} (each optional)
    def update
      errors = Validators::Util.errors
      attrs = {}
      attrs[:name] = Validators::Util.string(body["name"], "name", errors, @form.name, max: 120, required: true) if body.key?("name")
      if body.key?("targeting")
        attrs[:targeting] = Validators::Targeting.normalize(body["targeting"], "targeting", errors, with_scope: false)
      end
      if body.key?("template_key")
        key = body["template_key"].presence
        errors["template_key"] << "unknown template" unless key.nil? || CodForm::Form::TEMPLATE_KEYS.include?(key)
        gate!("templates") if key && key != @form.template_key
        attrs[:template_key] = key
      end

      normalized = nil
      if body.key?("draft_config")
        raw = body["draft_config"]
        errors.merge!(Validators::FormDraft.errors(raw)) { |_, left, right| left + right }
        if raw.is_a?(Hash)
          gate!("custom_fields") if Validators::FormDraft.custom_fields?(raw) && !Validators::FormDraft.custom_fields?(@form.draft_config)
          normalized = CodForm::Engine::FormConfig.normalize(raw)
          attrs[:draft_config] = normalized["config"]
          # There is one copy of a form, the live one: a form that could not go live is not saved.
          errors.merge!(engine_errors(normalized["errors"], "draft_config")) { |_, left, right| left + right }
        end
      end
      clean = errors.reject { |_, list| list.empty? }
      raise ValidationError.new(clean) if clean.any?

      old_targeting = @form.targeting
      old_name = @form.name
      @form.update!(attrs)
      audit("form.#{@form.id}.name", old_name, @form.name)
      if @form.targeting != old_targeting
        audit("form.#{@form.id}.targeting", old_targeting, @form.targeting)
        bump! # targeting decides which published form the storefront serves
      end

      normalized ||= CodForm::Engine::FormConfig.normalize(@form.draft_config)
      # Saving is publishing: the saved form is the live form.
      if Array(normalized["errors"]).empty? && @form.unpublished_changes?
        before = @form.published_version
        @form.publish!
        audit("form.#{@form.id}.published", before, @form.published_version)
        @publish_saved_changes = true
      end
      render json: form_json(@form).merge(
        "warnings" => Array(normalized["warnings"]),
        # Not fatal for a draft; POST …/publish answers 422 while this list is not empty.
        "publish_errors" => Array(normalized["errors"])
      )
    end

    # POST /cod_form/forms/:id/publish — 422 when the engine reports errors.
    def publish
      before = @form.published_version
      @form.publish! # raises RecordInvalid with publish_errors; bumps the shop config_version
      audit("form.#{@form.id}.published", before, @form.published_version)
      publish_storefront!
      render json: form_json(@form)
    end

    # POST /cod_form/forms/:id/discard_draft — draft_config = published_config
    def discard_draft
      @form.update!(draft_config: @form.published_config) if @form.unpublished_changes?
      render json: form_json(@form)
    end

    # POST /cod_form/forms/:id/duplicate — the copy has no targeting, so it serves nobody until
    # the merchant targets it.
    def duplicate
      ensure_room_for_another_form!
      copy = CodForm::Form.create!(
        shop_id: @shop.id, name: "#{@form.name} (copy)".first(120), is_default: false,
        status: CodForm::Form::STATUS_ACTIVE, position: (scope.maximum(:position) || 0) + 1,
        targeting: { "product_ids" => [], "collection_ids" => [] }, template_key: @form.template_key,
        draft_config: @form.draft_config, published_config: @form.published_config,
        published_version: @form.published? ? 1 : 0, published_at: @form.published? ? Time.current : nil
      )
      audit("form.#{copy.id}.created", "", copy.name)
      render json: form_json(copy), status: :created
    end

    # POST /cod_form/forms/:id/make_default
    def make_default
      invalid!("status", "an archived form cannot be the default") unless @form.active?
      invalid!("base", "publish the form before making it the default") unless @form.published?

      unless @form.is_default
        previous = scope.find_by(is_default: true)
        CodForm::Form.transaction do
          scope.where(is_default: true).update_all(is_default: false, updated_at: Time.current)
          @form.update!(is_default: true)
        end
        audit("form.default", previous&.id, @form.id)
        bump!
      end
      render json: { "items" => list_items }
    end

    # DELETE /cod_form/forms/:id — archives. The default form cannot be archived.
    def destroy
      invalid!("base", "the default form cannot be archived") if @form.is_default

      @form.update!(status: CodForm::Form::STATUS_ARCHIVED)
      audit("form.#{@form.id}.status", "active", "archived")
      bump!
      head :no_content
    end

    private

    def scope
      CodForm::Form.where(shop_id: @shop.id)
    end

    def load_form
      @form = scope.active.find(params[:id])
    end

    def ensure_room_for_another_form!
      count = scope.active.count
      gate!("multiple_forms") if count >= 1
      return if count < CodForm::Form::MAX_FORMS_PER_SHOP

      invalid!("base", "a shop can have at most #{CodForm::Form::MAX_FORMS_PER_SHOP} forms")
    end

    def list_items
      CodForm::Form.default_for(@shop)
      scope.active.order(is_default: :desc).ordered.map do |form|
        {
          "id" => form.id, "name" => form.name, "is_default" => form.is_default, "status" => form.status,
          "position" => form.position, "targeting" => form.targeting,
          "published_at" => iso(form.published_at), "published_version" => form.published_version,
          "has_unpublished_changes" => form.unpublished_changes?
        }
      end
    end

    def form_json(form)
      {
        "id" => form.id, "name" => form.name, "is_default" => form.is_default,
        "status" => form.status, "position" => form.position,
        "targeting" => form.targeting, "template_key" => form.template_key,
        "draft_config" => form.draft_config, "published_config" => form.published_config,
        "published_version" => form.published_version, "published_at" => iso(form.published_at),
        "has_unpublished_changes" => form.unpublished_changes?
      }
    end

    # [{"code", "name"}] for the countries that have an address / phone schema (WS2's
    # config/cod_form/countries.json); any other country uses the `default` schema.
    def countries
      data = CodForm::Cache.store.fetch("codf:admin:countries", expires_in: 1.hour) do
        JSON.parse(File.read(Rails.root.join(COUNTRIES_PATH)))
      end
      codes = data.is_a?(Hash) ? data.keys.select { |code| code.match?(/\A[A-Z]{2}\z/) } : []
      codes.map { |code| { "code" => code, "name" => (data[code].is_a?(Hash) && data[code]["name"]) || COUNTRY_NAMES[code] || code } }
    rescue StandardError
      COUNTRY_NAMES.map { |code, name| { "code" => code, "name" => name } }
    end
  end
end
