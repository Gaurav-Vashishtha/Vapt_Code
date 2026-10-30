module Api
  module Whatsapp
    class EventsController < AuthenticatedController
      def index
        render json: { events: ::Whatsapp::EventRegistry.as_json }
      end
    end
  end
end
