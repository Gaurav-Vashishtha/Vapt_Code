module Api
  class PrepaidTemplatesController < AuthenticatedController
    def index
      render json: { entries: ::Whatsapp::PrepaidTemplateLibrary.as_json }
    end
  end
end
