# frozen_string_literal: true

module CodFormAdmin
  # Shipping rates of the form (D.15, C.3; SHP-1..6, SHP-8).
  class ShippingRatesController < BaseController
    MAX_UPLOAD_BYTES = CodForm::ShippingCsvImporter::MAX_BYTES

    before_action :load_rate, only: %i[update destroy]

    # GET /cod_form/shipping_rates[?page=1] — every rate without `page` (the screen pages at 200
    # client-side); with `page`, 200 per page plus `meta`.
    def index
      if params[:page].present?
        rates, meta = paginate(scope.ordered, per: 200)
        render json: { "items" => rates.map(&:to_engine_hash), "meta" => meta }
      else
        render json: { "items" => items }
      end
    end

    def create
      attrs = validated!(Validators::ShippingRate.normalize(body))
      attrs["position"] = (scope.maximum(:position) || -1) + 1 unless body.key?("position")
      rate = CodForm::ShippingRate.create!(attrs.merge("shop_id" => @shop.id, "source" => CodForm::ShippingRate::SOURCE_MANUAL))
      audit("shipping_rate.#{rate.id}.created", "", rate.name)
      stamp_setup_state("shipping_rate_added_at")
      bump!
      render json: rate.to_engine_hash, status: :created
    end

    def update
      old = @rate.to_engine_hash
      @rate.update!(validated!(Validators::ShippingRate.normalize(body, current: old.except("id", "source"))))
      audit_changes("shipping_rate.#{@rate.id}", old, @rate.to_engine_hash)
      bump!
      render json: @rate.to_engine_hash
    end

    def destroy
      @rate.destroy!
      audit("shipping_rate.#{@rate.id}.deleted", @rate.name, "")
      bump!
      head :no_content
    end

    # POST /cod_form/shipping_rates/reorder  {"ids": [4, 2, 9]}
    def reorder
      ids = Array(body["ids"]).map { |id| Validators::Util.to_int(id) }
      invalid!("ids", "must be a list of rate ids") if ids.empty? || ids.any?(&:nil?) || ids.uniq.size != ids.size

      known = scope.where(id: ids).pluck(:id)
      invalid!("ids", "contains an unknown rate") if known.size != ids.size

      CodForm::ShippingRate.transaction do
        ids.each_with_index { |id, position| scope.where(id: id).update_all(position: position, updated_at: Time.current) }
        # Rates that were not listed keep their relative order after the listed ones.
        scope.where.not(id: ids).ordered.pluck(:id).each_with_index do |id, offset|
          scope.where(id: id).update_all(position: ids.size + offset)
        end
      end
      audit("shipping_rates.order", "", ids.join(","))
      bump!
      render json: { "items" => items }
    end

    # POST /cod_form/shipping_rates/import_csv  multipart: file, mode=append|replace
    # → {"created": 12, "errors": [{"row": 3, "message": "…"}]}
    def import_csv
      file = params[:file]
      invalid!("file", "is required") unless file.respond_to?(:read)
      invalid!("file", "is larger than 1 MB") if file.respond_to?(:size) && file.size.to_i > MAX_UPLOAD_BYTES

      mode = params[:mode].to_s == "replace" ? "replace" : "append"
      before = scope.count
      result = CodForm::ShippingCsvImporter.call(shop: @shop, content: file.read, mode: mode)
      if result["created"].positive?
        audit("shipping_rates.import_csv.#{mode}", before, scope.count)
        stamp_setup_state("shipping_rate_added_at")
        bump!
      end
      render json: result
    end

    private

    def scope
      CodForm::ShippingRate.where(shop_id: @shop.id)
    end

    def load_rate
      @rate = scope.find(params[:id])
    end

    def items
      scope.ordered.map(&:to_engine_hash)
    end
  end
end
