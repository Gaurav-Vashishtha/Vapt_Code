class DiscountsController < AuthenticatedController
  before_action :set_shop
  before_action :set_discount, only: %i[show update destroy activate deactivate resync]

  rescue_from ActiveRecord::RecordNotUnique do
    render json: { errors: ["A discount with this code already exists."] }, status: :unprocessable_entity
  end

  # GET /discounts
  def index
    render json: @shop.discounts.order(display_order: :asc, created_at: :desc)
  end

  # GET /discounts/:id
  def show
    render json: @discount
  end

  # POST /discounts
  def create
    discount = @shop.discounts.new(normalized_attributes)

    if discount.save
      discount.sync_to_shopify!
      render json: discount, status: :created
    else
      render json: { errors: discount.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /discounts/:id
  def update
    if @discount.update(normalized_attributes)
      @discount.sync_to_shopify!
      render json: @discount
    else
      render json: { errors: @discount.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /discounts/:id
  def destroy
    result = ShopifyServices::Discounts::Destroy.call(@discount)
    @discount.destroy
    render json: { ok: true, shopify_removed: result[:ok], shopify_error: result[:error] }
  end

  # POST /discounts/:id/activate
  def activate
    @discount.update!(is_active: true)
    @discount.sync_to_shopify!
    render json: @discount
  end

  # POST /discounts/:id/deactivate — removes from Shopify so it stops working at checkout.
  def deactivate
    ShopifyServices::Discounts::Destroy.call(@discount)
    @discount.update!(is_active: false, shopify_gid: nil, sync_status: "pending")
    render json: @discount
  end

  # POST /discounts/:id/resync — retry a failed sync.
  def resync
    @discount.sync_to_shopify!
    render json: @discount
  end

  # POST /discounts/validate_exceptions — keeps only product gids in the collections.
  def validate_exceptions
    products = ShopifyServices::CollectionMembershipService.call(
      @shop,
      product_gids: gid_array(params[:product_gids]),
      collection_gids: gid_array(params[:collection_gids])
    )
    render json: { products: products }
  end

  private

  def set_discount
    @discount = @shop.discounts.find(params[:id])
  end

  def normalized_attributes
    attrs = discount_params.to_h
    attrs["product_gids"] = gid_array(attrs["product_gids"]) if attrs.key?("product_gids")
    attrs["collection_gids"] = gid_array(attrs["collection_gids"]) if attrs.key?("collection_gids")
    attrs["excluded_product_gids"] = gid_array(attrs["excluded_product_gids"]) if attrs.key?("excluded_product_gids")
    attrs
  end

  def gid_array(raw)
    list = raw.is_a?(Array) ? raw : raw.to_s.split(",")
    list.map(&:to_s).map(&:strip).reject(&:blank?)
  end

  def discount_params
    params.require(:discount).permit(
      :title, :method, :code, :discount_type, :value, :applies_to,
      :minimum_requirement_type, :minimum_requirement_value, :usage_limit, :once_per_customer,
      :starts_at, :ends_at,
      :combines_with_order, :combines_with_product, :combines_with_shipping,
      :widget_enabled, :headline, :unlock_text, :display_order, :is_active,
      product_gids: [], collection_gids: [], excluded_product_gids: [],
      bxgy_config: [
        :buys_type, :buys_value, :buys_items, :gets_qty, :gets_effect_value,
        { buys_product_gids: [], buys_collection_gids: [] }
      ]
    )
  end
end
