# frozen_string_literal: true

module CodFormAdmin
  # Tracking pixels of the form (D.15, C.6; TRK-2, TRK-8).
  #
  #   402  first_pixel / extra_pixels (2nd+ pixel of a platform) / pixels_p3 (Snapchat, Pinterest,
  #        product-specific pixels)
  #   422  {"error": "pixel_limit"} beyond 5 pixels per platform
  # `access_token` is write-only: responses carry `access_token_masked` only.
  class PixelsController < BaseController
    before_action :load_pixel, only: %i[update destroy test]

    def index
      render json: { "items" => scope.ordered.map { |pixel| pixel_json(pixel) } }
    end

    def create
      attrs = validated!(Validators::Pixel.normalize(body))
      others = scope.for_platform(attrs["platform"]).count
      if others >= Validators::Pixel::MAX_PER_PLATFORM
        raise ValidationError.new({ "platform" => ["at most #{Validators::Pixel::MAX_PER_PLATFORM} pixels per platform"] }, code: "pixel_limit")
      end
      Validators::Pixel.required_features(attrs, others_on_platform: others).each { |feature| gate!(feature) }

      pixel = CodForm::TrackingPixel.create!(attrs.merge("shop_id" => @shop.id))
      audit("pixel.#{pixel.id}.created", "", "#{pixel.platform}: #{pixel.pixel_id}")
      bump!
      render json: pixel_json(pixel), status: :created
    end

    def update
      old = pixel_json(@pixel)
      attrs = validated!(Validators::Pixel.normalize(body, current: old.except("id", "access_token_masked")))
      if attrs.dig("targeting", "scope") == "selected" && old.dig("targeting", "scope") != "selected"
        gate!("pixels_p3")
      end

      token_changed = attrs.key?("access_token") && attrs["access_token"] != @pixel.access_token
      @pixel.update!(attrs)
      audit_changes("pixel.#{@pixel.id}", old.except("access_token_masked"), pixel_json(@pixel).except("access_token_masked"))
      audit("pixel.#{@pixel.id}.access_token", "", "[changed]") if token_changed
      bump!
      render json: pixel_json(@pixel)
    end

    def destroy
      @pixel.destroy!
      audit("pixel.#{@pixel.id}.deleted", "#{@pixel.platform}: #{@pixel.pixel_id}", "")
      bump!
      head :no_content
    end

    # POST /cod_form/pixels/:id/test → {"ok": true, "response": {...}} (one synthetic server event)
    def test
      render json: CodForm::Tracking::TestEvent.call(@pixel)
    end

    private

    def scope
      CodForm::TrackingPixel.where(shop_id: @shop.id)
    end

    def load_pixel
      @pixel = scope.find(params[:id])
    end

    def pixel_json(pixel)
      { "id" => pixel.id, "platform" => pixel.platform, "pixel_id" => pixel.pixel_id,
        "access_token_masked" => pixel.access_token_masked, "enabled" => pixel.enabled,
        "position" => pixel.position, "targeting" => pixel.targeting, "config" => pixel.config }
    end
  end
end
