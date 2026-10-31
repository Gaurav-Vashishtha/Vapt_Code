# frozen_string_literal: true

class EmailToolController < ApplicationController
  layout "email_tool"
  before_action :authenticate_admin!
  skip_before_action :verify_authenticity_token, only: [:rules_evaluate]
  rescue_from StandardError, with: :log_deliveries_error

  def index
    @rules_count = EmailRule.count
    @active_rules_count = EmailRule.active.count
    @templates_count = EmailTemplate.count
    @pending_deliveries_count = ScheduledEmail.pending.count
    @sent_deliveries_count = ScheduledEmail.sent.count
    @opened_count = ScheduledEmail.sent.where.not(opened_at: nil).count
    @open_rate = @sent_deliveries_count.positive? ? (100.0 * @opened_count / @sent_deliveries_count).round(1) : 0
    @last_run = (Sidekiq::Cron::Job.find("email_scheduler_job").last_enqueue_time if defined?(Sidekiq::Cron::Job)) rescue nil
  end

  def rules
    @rules = EmailRule.includes(:email_template).order(created_at: :desc).page(params[:page]).per(25)
  end

  def rules_new
    @rule = EmailRule.new(active: true, date_rule_type: "days_after_installation", date_rule_value: 3, conditions: [], date_rule_column: "shops.created_at", target: "shops")
    @templates = EmailTemplate.order(:name)
    set_rule_form_options
  end

  def rules_create
    @rule = EmailRule.new(rule_params)
    if @rule.save
      redirect_to email_tool_rules_path, notice: "Rule created."
    else
      @templates = EmailTemplate.order(:name)
      set_rule_form_options
      render :rules_new, status: :unprocessable_entity
    end
  end

  def rules_edit
    @rule = EmailRule.find(params[:id])
    @templates = EmailTemplate.order(:name)
    set_rule_form_options
  end

  def rules_update
    @rule = EmailRule.find(params[:id])
    if @rule.update(rule_params)
      redirect_to email_tool_rules_path, notice: "Rule updated."
    else
      @templates = EmailTemplate.order(:name)
      set_rule_form_options
      render :rules_edit, status: :unprocessable_entity
    end
  end

  def rules_destroy
    @rule = EmailRule.find(params[:id])
    @rule.destroy
    redirect_to email_tool_rules_path, notice: "Rule deleted."
  end

  def rules_evaluate
    rule = if params[:id].present?
             r = EmailRule.find(params[:id])
             r.assign_attributes(rule_params)
             r
           else
             EmailRule.new(rule_params)
           end
    target = EmailRuleEvaluatorService.rule_target(rule)
    count = if target == "uninstalled_shops"
              EmailRuleEvaluatorService.candidate_uninstalled_shop_ids_for_rule(rule).size
            else
              EmailRuleEvaluatorService.candidate_shop_ids_for_rule(rule).size
            end
    render json: { count: count, target: target }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Rule not found" }, status: :not_found
  rescue ArgumentError, StandardError => e
    render json: { error: e.message, count: 0 }, status: :unprocessable_entity
  end

  def templates
    @templates = EmailTemplate.order(:name).page(params[:page]).per(25)
  end

  def templates_new
    @template = EmailTemplate.new
  end

  def templates_create
    @template = EmailTemplate.new(template_params)
    if @template.save
      redirect_to email_tool_templates_path, notice: "Template created."
    else
      render :templates_new, status: :unprocessable_entity
    end
  end

  def templates_edit
    @template = EmailTemplate.find(params[:id])
  end

  def templates_update
    @template = EmailTemplate.find(params[:id])
    if @template.update(template_params)
      redirect_to email_tool_templates_path, notice: "Template updated."
    else
      render :templates_edit, status: :unprocessable_entity
    end
  end

  def templates_destroy
    @template = EmailTemplate.find(params[:id])
    if @template.email_rules.any?
      redirect_to email_tool_templates_path, alert: "Cannot delete template in use by rules."
    else
      @template.destroy
      redirect_to email_tool_templates_path, notice: "Template deleted."
    end
  end

  def templates_preview
    template_like = if params[:template_id].present?
      @template = EmailTemplate.find(params[:template_id])
      @template
    else
      OpenStruct.new(subject: params[:subject].to_s, body: params[:body].to_s)
    end
    subject = template_like.subject
    body = template_like.body
    sample_shop = params[:shop_id].present? ? Shop.find_by(id: params[:shop_id]) : Shop.joins(:setting).first
    sample_shop ||= Shop.first
    if sample_shop
      @preview_subject = EmailTemplateRendererService.render_subject(template_like, shop: sample_shop)
      @preview_body = EmailTemplateRendererService.render_body(template_like, shop: sample_shop)
    else
      @preview_subject = subject
      @preview_body = body.presence || "<p>No sample shop available for preview.</p>"
    end
    render "email_tool/templates/preview", layout: "email_tool_preview"
  end

  def deliveries
    @status_filter = params[:status].presence_in(%w[all pending sent skipped failed rescheduled]) || "all"
    scope = ScheduledEmail.includes(:email_rule, :shop, :uninstalled_shop, :email_click_redirects).order(created_at: :desc)
    scope = scope.where(status: @status_filter) unless @status_filter == "all"
    page = [params[:page].to_i, 1].max
    @deliveries = scope.page(page).per(25)
  end

  def delivery_open_stats
    date_expr = Arel.sql("DATE(#{ScheduledEmail.quoted_table_name}.sent_at)")
    raw = ScheduledEmail.sent
      .group(:email_rule_id, date_expr)
      .select(
        "#{ScheduledEmail.quoted_table_name}.email_rule_id",
        "#{date_expr} AS sent_date",
        "COUNT(*) AS sent_count",
        "SUM(CASE WHEN #{ScheduledEmail.quoted_table_name}.opened_at IS NOT NULL THEN 1 ELSE 0 END) AS opened_count"
      )
      .order(Arel.sql("email_rule_id"), Arel.sql("sent_date DESC"))
    @rule_ids = raw.map(&:email_rule_id).uniq
    @rules_by_id = EmailRule.where(id: @rule_ids).index_by(&:id)
    @stats = raw.to_a
    # Click count: distinct scheduled_emails (per rule, per day) that had at least one click
    se = ScheduledEmail.quoted_table_name
    clicked_by_distinct = ScheduledEmail.sent
      .joins(:email_click_redirects)
      .where.not(email_click_redirects: { clicked_at: nil })
      .group(:email_rule_id, date_expr)
      .count("DISTINCT #{se}.id")
    # Normalize keys to [rule_id, "YYYY-MM-DD"] so view can look up with row.sent_date
    @clicked_count_by_key = clicked_by_distinct.transform_keys do |(rid, d)|
      [rid, d.respond_to?(:strftime) ? d.strftime("%Y-%m-%d") : d.to_s]
    end
  end

  def run_now
    EmailSchedulerJob.perform_async
    redirect_to email_tool_path, notice: "Scheduler job enqueued. It will run shortly."
  end

  def delivery_destroy
    delivery = ScheduledEmail.find(params[:id])
    delivery.destroy
    redirect_to email_tool_deliveries_path(status: params[:status]), notice: "Scheduled email deleted."
  rescue ActiveRecord::RecordNotFound
    redirect_to email_tool_deliveries_path, alert: "Delivery not found."
  end

  private

  def authenticate_admin!
    http_basic_authenticate_or_request_with(
      name: ENV.fetch("ADMIN_USER", nil),
      password: ENV.fetch("ADMIN_PASS", nil)
    )
  end

  def log_deliveries_error(e)
    if action_name == "deliveries"
      Rails.logger.error "[EmailToolController#deliveries] #{e.class}: #{e.message}"
      Rails.logger.error e.backtrace.first(30).join("\n")
    end
    raise
  end

  def rule_params
    p = params.require(:email_rule).permit(
      :name, :slug, :email_template_id, :date_rule_type, :date_rule_value, :date_rule_column, :target, :active,
      :scheduled_hour, :scheduled_minute,
      :conditions
    )
    cond = params[:email_rule][:conditions]
    if cond.present?
      arr = cond.is_a?(Array) ? cond : cond.values
      p[:conditions] = arr.map do |c|
        next nil if c.blank?
        h = (c.is_a?(ActionController::Parameters) ? c.permit(:table, :column, :op, :value, :combiner) : c).to_h
        h if h["table"].present? && h["column"].present? && h["op"].present?
      end.compact
    end
    p
  end

  def set_rule_form_options
    @date_columns_for_rule = EmailRule::DATE_COLUMNS_FOR_RULE
    @shop_columns_for_condition = EmailRule.shop_columns_for_condition_options
    @settings_columns_for_condition = EmailRule.settings_columns_for_condition_options
    @uninstalled_shop_columns_for_condition = EmailRule.uninstalled_shop_columns_for_condition_options
  end

  def template_params
    params.require(:email_template).permit(:name, :subject, :body)
  end
end
