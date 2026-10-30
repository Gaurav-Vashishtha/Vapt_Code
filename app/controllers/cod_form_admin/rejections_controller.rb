# frozen_string_literal: true

module CodFormAdmin
  # Blocked attempts list (D.15, B.9, FRD-6). Read-only; subjects are stored masked.
  class RejectionsController < BaseController
    # GET /cod_form/rejections?page=1&reason=&stage=
    def index
      list = CodForm::Rejection.where(shop_id: @shop.id)
      list = list.where(reason_code: params[:reason].to_s) if params[:reason].present?
      list = list.where(stage: params[:stage].to_s) if params[:stage].present?
      rows, meta = paginate(list.recent)
      render json: { "items" => rows.map { |row| rejection_json(row) }, "meta" => meta }
    end

    private

    def rejection_json(row)
      { "id" => row.id, "session_public_id" => row.session_public_id, "reason_code" => row.reason_code,
        "stage" => row.stage, "subject_kind" => row.subject_kind, "subject_masked" => row.subject_masked,
        "detail" => row.detail, "ip" => row.ip, "created_at" => iso(row.created_at) }
    end
  end
end
