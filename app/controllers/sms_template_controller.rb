class SmsTemplateController < AuthenticatedController
  before_action :set_shop, only: %i[create]
  # POST /headers
  # POST /headers.json
  def create

    # byebug  # Start a debugging session here
    puts "Received parameters: #{params.inspect}"  # Log the incoming parameters

    new_params = headers_params
    
    if @shop.headers.new(new_params).save
      render json: { message: "Settings saved successfully" }, status: :ok
    else
      render json: { message: "Something went wrong" }, status: :unprocessable_entity
    end
  end

  private

  # Only allow a list of trusted parameters through.
  def headers_params
    params.require(:header).permit(
      :country_codes,
      :header_id,
      :dlt_principal_entity_id
    )
  end
end
