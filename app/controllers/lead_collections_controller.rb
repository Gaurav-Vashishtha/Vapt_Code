class LeadCollectionsController < ApplicationController
  def new
    @lead_collection = LeadCollection.new(prefill_params)
  end

  def create
    @lead_collection = LeadCollection.new(lead_collection_params)

    if @lead_collection.save
      LeadCollectionMailer.notify_whatsapp_approvers(@lead_collection.id).deliver_later
      redirect_to new_lead_collection_path, notice: "Thanks for reaching out. The COD King team will contact you 1-1 soon."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def prefill_params
    permitted = params.permit(
      :email,
      :phone,
      :phone_number,
      :purpose,
      :preferred_time_to_connect,
      :website,
      :notes
    )

    {
      email: permitted[:email],
      phone_number: permitted[:phone_number].presence || permitted[:phone],
      purpose: permitted[:purpose],
      preferred_time_to_connect: permitted[:preferred_time_to_connect],
      website: permitted[:website],
      notes: permitted[:notes]
    }.compact
  end

  def lead_collection_params
    params.require(:lead_collection).permit(
      :email,
      :phone_number,
      :purpose,
      :preferred_time_to_connect,
      :website,
      :notes
    )
  end
end
