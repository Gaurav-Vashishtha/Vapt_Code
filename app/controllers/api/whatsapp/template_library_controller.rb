module Api
  module Whatsapp
    class TemplateLibraryController < AuthenticatedController
      def index
        render json: { entries: ::Whatsapp::TemplateLibrary.as_json }
      end
    end
  end
end
