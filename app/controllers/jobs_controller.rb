# frozen_string_literal: true

class JobsController < AuthenticatedController

  def status
    if params[:job_id]
      data = Sidekiq::Status::get_all params[:job_id]
      if data && data["status"]
        render json: data
      else
        render json: { error: 'STATUS_DATA_EXPIRED' }
      end
    else
      render json: { error: 'NO_JOB_ID'}
    end
  end
end
