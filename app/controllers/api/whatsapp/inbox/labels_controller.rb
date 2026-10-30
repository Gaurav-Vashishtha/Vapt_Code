# frozen_string_literal: true

module Api
  module Whatsapp
    module Inbox
      class LabelsController < BaseController
        before_action :load_label, only: %i[update destroy]

        def index
          WhatsappInboxLabel.ensure_defaults!(@shop)
          render json: { labels: WhatsappInboxLabel.where(shop_id: @shop.id).ordered.map(&:as_inbox_json) }
        end

        def create
          position = WhatsappInboxLabel.where(shop_id: @shop.id).maximum(:position).to_i + 1
          label = WhatsappInboxLabel.new(label_params.merge(shop_id: @shop.id, position: position))
          save_and_render(label, :created)
        end

        def update
          @label.assign_attributes(label_params)
          save_and_render(@label, :ok)
        end

        def destroy
          return render_error('system_label', "Built-in labels can't be deleted. You can rename them.") if @label.system?

          @label.destroy!
          render json: { ok: true }
        end

        private

        def load_label
          @label = WhatsappInboxLabel.where(shop_id: @shop.id).find_by(id: params[:id])
          render_error('not_found', 'Label not found', :not_found) unless @label
        end

        def label_params
          params.slice(:name, :color).permit(:name, :color).to_h
        end

        def save_and_render(label, status)
          if label.save
            render json: { label: label.as_inbox_json }, status: status
          else
            render_error('invalid', label.errors.full_messages.first)
          end
        rescue ActiveRecord::RecordNotUnique
          render_error('invalid', 'Name is already used by another label')
        end
      end
    end
  end
end
