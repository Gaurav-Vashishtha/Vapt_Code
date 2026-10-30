module Api
  module Whatsapp
    class SegmentsController < AuthenticatedController
      ACTIVE_CAMPAIGN_STATUSES = %w[scheduled building testing sending paused retry_waiting].freeze

      def index
        segments = WhatsappSegment.where(shop_id: @shop.id).order(created_at: :desc).limit(100)
        segments.each { |s| s.refresh_count! if s.counted_at.nil? || s.counted_at < 10.minutes.ago }
        render json: { segments: segments.map { |s| serialize(s) } }
      end

      def create
        segment = WhatsappSegment.new(shop_id: @shop.id, name: params[:name].to_s.strip,
                                      description: params[:description].to_s.presence,
                                      filters: WhatsappSegment.sanitize_filters(filters_param))
        if segment.save
          segment.refresh_count!
          render json: { segment: serialize(segment.reload) }, status: :created
        else
          render_error(segment.errors.full_messages.to_sentence)
        end
      end

      def update
        segment = find_segment or return
        segment.name = params[:name].to_s.strip if params.key?(:name)
        segment.description = params[:description].to_s.presence if params.key?(:description)
        segment.filters = WhatsappSegment.sanitize_filters(filters_param) if params.key?(:filters)
        if segment.save
          segment.refresh_count!
          render json: { segment: serialize(segment.reload) }
        else
          render_error(segment.errors.full_messages.to_sentence)
        end
      end

      def destroy
        segment = find_segment or return
        in_use = WhatsappCampaign.where(shop_id: @shop.id, whatsapp_segment_id: segment.id, status: ACTIVE_CAMPAIGN_STATUSES)
        return render_error('This segment is used by an active campaign. Cancel or finish it first.') if in_use.exists?
        segment.destroy
        head :no_content
      end

      def preview
        filters = WhatsappSegment.sanitize_filters(filters_param)
        scope = ::Whatsapp::SegmentQuery.scope(@shop.id, filters)
        render json: {
          count: scope.count,
          sample: scope.order(updated_at: :desc).limit(5).map { |c| { phone: c.phone, name: c.display_name, tags: Array(c.tags) } }
        }
      rescue StandardError => e
        Rails.logger.warn("[SegmentsController] preview failed: #{e.message}")
        render json: { count: 0, sample: [] }
      end

      private

      def filters_param
        raw = params[:filters]
        raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
      rescue StandardError
        {}
      end

      def find_segment
        segment = WhatsappSegment.find_by(id: params[:id], shop_id: @shop.id)
        render(json: { error: 'Segment not found' }, status: :not_found) unless segment
        segment
      end

      def render_error(msg)
        render json: { error: msg }, status: :unprocessable_entity
        nil
      end

      def serialize(s)
        { id: s.id, name: s.name, description: s.description, filters: s.filters,
          count: s.cached_count, counted_at: s.counted_at, created_at: s.created_at }
      end
    end
  end
end
