# frozen_string_literal: true

module Api
  module V1
    module Cb
      class EventsController < BaseController
        def index
          refresh = ActiveModel::Type::Boolean.new.cast(params[:refresh])
          catalog = ::CustomBranded::ParcelxEventCatalog.load(client: client, refresh: refresh)
          render json: { events: catalog.events, source: catalog.source, warning: catalog.warning }
        rescue ::CustomBranded::ParcelxEventCatalog::Unavailable => e
          render_error('events_unavailable', :bad_gateway, detail: e.message)
        end
      end
    end
  end
end
