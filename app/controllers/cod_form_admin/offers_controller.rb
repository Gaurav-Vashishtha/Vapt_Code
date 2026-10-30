# frozen_string_literal: true

module CodFormAdmin
  # Offers (D.15, C.4): quantity offers, order bumps, upsells, downsells, thresholds, pre-purchase upsells.
  #
  #   402 per gate: quantity_offers, order_bumps, upsell, downsell, threshold_offers
  #   422 errors.targeting on an OFF-2 overlap (a product in two active quantity offers)
  #   422 errors.status when the active limit is reached (50 quantity offers, 20 bumps, 1 downsell)
  class OffersController < BaseController
    LIST_PARAM_TYPES = { "bumps" => "bump", "upsells" => "upsell", "downsells" => "downsell", "thresholds" => "threshold",
                         "pre_upsells" => "pre_upsell", "bundles" => "bundle" }.freeze

    before_action :load_offer, only: %i[show update destroy status]

    # GET /cod_form/offers?type=quantity[&status=active][&page=1]
    def index
      list = scope.where.not(status: CodForm::Offer::STATUS_ARCHIVED)
      type = LIST_PARAM_TYPES[params[:type].to_s] || params[:type].to_s
      list = list.of_type(type) if type.present?
      list = list.where(status: params[:status].to_s) if params[:status].present?
      list = list.order(:offer_type).ordered

      if params[:page].present?
        offers, meta = paginate(list)
        render json: { "items" => offers.map(&:to_engine_hash), "meta" => meta }
      else
        render json: { "items" => list.limit(500).map(&:to_engine_hash) }
      end
    end

    def show
      render json: @offer.to_engine_hash
    end

    def create
      attrs = validated!(Validators::Offer.normalize(body))
      gate!(Validators::Offer::GATES.fetch(attrs["offer_type"]))
      warnings = activation_checks!(attrs, nil)

      offer = CodForm::Offer.create!(attrs.merge("shop_id" => @shop.id))
      audit("offer.#{offer.id}.created", "", "#{offer.offer_type}: #{offer.name}")
      refresh_pre_upsell(offer)
      bump!
      render json: offer.to_engine_hash.merge("warnings" => warnings), status: :created
    end

    def update
      locked_by_test!
      old = @offer.to_engine_hash
      attrs = validated!(Validators::Offer.normalize(body, current: old))
      gate!(Validators::Offer::GATES.fetch(attrs["offer_type"]))
      warnings = activation_checks!(attrs, @offer)

      @offer.update!(attrs)
      audit_changes("offer.#{@offer.id}", old, @offer.to_engine_hash)
      refresh_pre_upsell(@offer)
      bump!
      render json: @offer.to_engine_hash.merge("warnings" => warnings)
    end

    # DELETE /cod_form/offers/:id — archives (orders and sessions keep referring to the offer).
    def destroy
      locked_by_test!
      old = @offer.status
      @offer.update!(status: CodForm::Offer::STATUS_ARCHIVED)
      audit("offer.#{@offer.id}.status", old, @offer.status)
      bump!
      head :no_content
    end

    # POST /cod_form/offers/:id/status  {"status": "active" | "paused"}
    def status
      target = body["status"].to_s
      invalid!("status", "must be one of: active, paused") unless %w[active paused].include?(target)

      old = @offer.status
      warnings = []
      if target == "active"
        gate!(Validators::Offer::GATES.fetch(@offer.offer_type))
        warnings = activation_checks!(@offer.to_engine_hash.merge("status" => "active"), @offer)
      end
      @offer.update!(status: target)
      audit("offer.#{@offer.id}.status", old, target)
      refresh_pre_upsell(@offer) if target == "active"
      bump!
      render json: @offer.to_engine_hash.merge("warnings" => warnings)
    end

    private

    def scope
      CodForm::Offer.where(shop_id: @shop.id)
    end

    # A pre-purchase upsell rule lists the products it offers (the chosen products or the
    # collection's) right away, so the form and the preview have them. Shopify being slow only
    # leaves the previous list in place.
    def refresh_pre_upsell(offer)
      return unless CodForm::PreUpsellCatalog::TYPES.include?(offer.offer_type)

      CodForm::PreUpsellCatalog.refresh!(offer)
      offer.reload
    end

    def load_offer
      @offer = scope.find(params[:id])
    end

    # OFF-12: an offer that is a variant of a running test is locked.
    def locked_by_test!
      invalid!("base", "this offer is part of a running A/B test") if @offer.ab_test_id.present?
    end

    # Limits and OFF-2 for an offer that is (becoming) active. Returns the overlap warnings.
    def activation_checks!(attrs, record)
      return [] unless attrs["status"] == CodForm::Offer::STATUS_ACTIVE

      others = scope.active.of_type(attrs["offer_type"])
      others = others.where.not(id: record.id) if record
      becoming_active = record.nil? || !record.active?
      if becoming_active
        message = Validators::Offer.limit_error(attrs["offer_type"], others.count)
        invalid!("status", message) if message
      end
      return [] unless attrs["offer_type"] == "quantity"

      other_hashes = others.map(&:to_engine_hash)
      conflicts = Validators::Offer.product_conflicts(attrs, other_hashes)
      if conflicts.any?
        ids = conflicts.map { |conflict| conflict["product_id"] }.first(20).join(", ")
        invalid!("targeting", "a product can be in only one active quantity offer (product ids: #{ids})")
      end
      Validators::Offer.overlap_warnings(attrs, other_hashes)
    end
  end
end
