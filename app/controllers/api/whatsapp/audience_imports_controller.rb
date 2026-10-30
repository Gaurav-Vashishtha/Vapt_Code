module Api
  module Whatsapp
    class AudienceImportsController < AuthenticatedController
      MAX_CSV_BYTES = 10.megabytes

      def create
        return render(json: { error: 'CSV file required.' }, status: :unprocessable_entity) if params[:file].blank?
        if params[:file].respond_to?(:size) && params[:file].size > MAX_CSV_BYTES
          return render(json: { error: 'CSV is too large (max 10 MB).' }, status: :unprocessable_entity)
        end

        # The raw content is persisted in the DB, not just Active Storage:
        # production uses the :local storage service, so a Sidekiq worker on
        # another host can't read the web server's disk (FileNotFoundError at
        # audience-build time). The DB copy makes parse + build host-agnostic.
        content = params[:file].read.dup.force_encoding('UTF-8').scrub

        import = WhatsappAudienceImport.new(shop_id: @shop.id, status: 'uploaded',
                                            raw_content: content,
                                            phone_column: params[:phone_column],
                                            name_column: params[:name_column],
                                            email_column: params[:email_column])
        if import.save
          ::Whatsapp::ImportCsvAudienceJob.new.perform(import.id)
          render json: serialize(import.reload), status: :created
        else
          render json: { error: import.errors.full_messages.to_sentence }, status: :unprocessable_entity
        end
      end

      def show
        import = WhatsappAudienceImport.find_by(id: params[:id], shop_id: @shop.id)
        return render(json: { error: 'Not found' }, status: :not_found) unless import
        render json: serialize(import)
      end

      # Column remapping from the wizard: re-parses inline so the new
      # phone-column pick immediately updates valid_count.
      def update
        import = WhatsappAudienceImport.find_by(id: params[:id], shop_id: @shop.id)
        return render(json: { error: 'Not found' }, status: :not_found) unless import

        import.update!(params.permit(:phone_column, :name_column, :email_column))
        ::Whatsapp::ImportCsvAudienceJob.new.perform(import.id)
        render json: serialize(import.reload)
      end

      private

      def serialize(import)
        { id: import.id, status: import.status, columns: import.columns,
          row_count: import.row_count, valid_count: import.valid_count,
          phone_column: import.phone_column, name_column: import.name_column,
          email_column: import.email_column, error: import.error }
      end
    end
  end
end
