# frozen_string_literal: true

class SmsTemplateApprovalsController < AuthenticatedController
  skip_before_action :verify_authenticity_token, only: %i[create], raise: false
  before_action :require_paid_plan!, only: %i[create]

  def index
    eligibility = template_management_eligibility
    types = SmsTemplateTypeConfig.active.order(:display_name)
    latest_by_type = SmsTemplateApproval
      .where(shop_id: @shop.id)
      .select("DISTINCT ON (template_type_key) *")
      .order("template_type_key, created_at DESC")
      .index_by(&:template_type_key)

    payload = types.map do |type|
      latest = latest_by_type[type.key]
      setting_value = @shop.setting&.public_send(type.target_column)
      {
        key: type.key,
        display_name: type.display_name,
        target_column: type.target_column,
        allowed_variables: type.allowed_variables,
        max_variables: type.max_variables,
        current_body: setting_value,
        latest_approval: latest && {
          id: latest.id,
          status: latest.status,
          body: latest.body,
          variables_used: latest.variables_used,
          submitted_at: latest.submitted_at,
          reviewed_at: latest.reviewed_at,
          review_reason: latest.review_reason
        }
      }
    end

    history = SmsTemplateApproval
      .where(shop_id: @shop.id)
      .order(created_at: :desc)
      .limit(30)
      .map do |row|
        {
          id: row.id,
          template_type_key: row.template_type_key,
          status: row.status,
          body: row.body,
          submitted_at: row.submitted_at,
          reviewed_at: row.reviewed_at,
          review_reason: row.review_reason
        }
      end

    render json: { types: payload, history: history, eligibility: eligibility }
  end

  def create
    service_result = SmsTemplateApprovalService.submit(
      shop: @shop,
      template_type_key: params[:template_type_key],
      body: params[:body],
      submitted_by: submitted_by_identity
    )

    if service_result.ok?
      render json: { ok: true, approval: service_result.record }, status: :created
    else
      render json: { ok: false, errors: service_result.errors }, status: :unprocessable_entity
    end
  end

  private

  def require_paid_plan!
    eligibility = template_management_eligibility
    return if eligibility[:allowed]

    render json: { ok: false, errors: [eligibility[:reason]] }, status: :forbidden
  end

  def submitted_by_identity
    @shop&.owner_email.presence || @shop&.shopify_domain.to_s
  end

  def template_management_eligibility
    plan_name = @shop&.plan&.name.to_s.downcase
    country_code = @shop&.country_code.to_s.upcase
    paid_plan = @shop&.charge_id.present? && plan_name != "free"
    special_countries = ENV.fetch("MSG_91_SPECIAL_COUNTRIES", "").split(",").map { |c| c.to_s.strip.upcase }.reject(&:blank?)

    return { allowed: false, reason: "Template approvals are available on paid plans only" } unless paid_plan

    if special_countries.include?(country_code)
      allowed_plans = ["enterprise", "enterprise plus", "india_budget"]
      plan_allowed = allowed_plans.any? { |p| plan_name.include?(p) }
      return {
        allowed: plan_allowed,
        reason: "For stores in MSG_91 special countries, SMS template management is available only on Enterprise, Enterprise Plus, or India Budget plans. Please upgrade to Enterprise or Enterprise Plus plan for custom templates."
      }
    end

    { allowed: true, reason: nil }
  end
end
