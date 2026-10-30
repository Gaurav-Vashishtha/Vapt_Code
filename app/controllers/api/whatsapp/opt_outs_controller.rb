module Api
  module Whatsapp
    class OptOutsController < AuthenticatedController
      def index
        scope = WhatsappOptOut.where(shop_id: @shop.id)
        scope = scope.where('phone_normalized ILIKE ?', "%#{params[:q].to_s.gsub(/\D/, '')}%") if params[:q].present?
        list = scope.order(opted_out_at: :desc).limit(200)
        render json: { opt_outs: list.map { |o| { phone: o.phone_normalized, reason: o.reason, opted_out_at: o.opted_out_at } }, total: scope.count }
      end

      def create
        phone = RtoOrder.normalize_phone(params[:phone]).to_s.gsub(/\D/, '')
        return render(json: { error: 'Valid phone required.' }, status: :unprocessable_entity) if phone.blank?
        WhatsappOptOut.record!(shop_id: @shop.id, phone_normalized: phone, reason: 'manual', source: 'admin')
        render json: { phone: phone }, status: :created
      end

      def destroy
        phone = RtoOrder.normalize_phone(params[:id]).to_s.gsub(/\D/, '')
        WhatsappOptOut.where(shop_id: @shop.id, phone_normalized: phone).delete_all
        head :no_content
      end
    end
  end
end
