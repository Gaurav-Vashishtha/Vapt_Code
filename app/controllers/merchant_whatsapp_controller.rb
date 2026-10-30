# frozen_string_literal: true

class MerchantWhatsappController < ApplicationController
  before_action :authenticate_admin!

  def index
    @account = OwnerWhatsappAccount.current
    @enabled = MerchantWhatsapp::Config.enabled?
    @live = MerchantWhatsapp::Config.live?
    @rules = MerchantWhatsappRule.order(:category, :name)
    @templates_count = OwnerWhatsappTemplate.count
    @queue_counts = ScheduledMerchantWhatsapp.group(:status).count
    @funnel = MerchantWhatsappLog.real.where("created_at >= ?", 30.days.ago).group(:status).count
  end

  def sender
    @account = OwnerWhatsappAccount.current || OwnerWhatsappAccount.new
  end

  def save_sender
    account = OwnerWhatsappAccount.current || OwnerWhatsappAccount.new
    attrs = sender_params.to_h
    attrs.delete("system_user_token") if attrs["system_user_token"].blank?
    account.assign_attributes(attrs)
    account.save!
    redirect_to merchant_whatsapp_path, notice: "Sender saved"
  rescue => e
    redirect_to merchant_whatsapp_sender_path, alert: e.message
  end

  def templates
    @templates = OwnerWhatsappTemplate.order(:name)
    @template = OwnerWhatsappTemplate.new(language: "en", category: "UTILITY", status: "approved")
  end

  def save_template
    template = params[:id].present? ? OwnerWhatsappTemplate.find(params[:id]) : OwnerWhatsappTemplate.new
    template.assign_attributes(template_params)
    template.buttons = parse_json(params[:buttons_json], [])
    template.variable_mapping = parse_json(params[:variable_mapping_json], {})
    template.save!
    redirect_to merchant_whatsapp_templates_path, notice: "Template saved"
  rescue => e
    redirect_to merchant_whatsapp_templates_path, alert: e.message
  end

  def create_meta_template
    buttons = Array(params[:btn_type]).each_index.map do |i|
      { "type" => Array(params[:btn_type])[i], "text" => Array(params[:btn_text])[i], "url" => Array(params[:btn_url])[i] }
    end
    record = MerchantWhatsapp::TemplateBuilder.create(
      name: params[:name], language: params[:language], category: params[:category],
      header_type: params[:header_type], header_text: params[:header_text], header_sample: params[:header_sample],
      header_image_url: params[:header_image_url], body: params[:body], body_samples: Array(params[:body_samples]),
      footer: params[:footer], buttons: buttons, variable_mapping: build_bindings
    )
    redirect_to merchant_whatsapp_templates_path, notice: "Template '#{record.name}' submitted to Meta (status: #{record.status})"
  rescue => e
    redirect_to merchant_whatsapp_templates_path, alert: "Create failed: #{e.message}"
  end

  def update_template_mapping
    template = OwnerWhatsappTemplate.find(params[:id])
    template.update!(variable_mapping: build_bindings)
    redirect_to merchant_whatsapp_templates_path, notice: "Binding saved for #{template.name}"
  rescue => e
    redirect_to merchant_whatsapp_templates_path, alert: e.message
  end

  def sync_templates
    count = MerchantWhatsapp::TemplateSync.call
    redirect_to merchant_whatsapp_templates_path, notice: "Synced #{count} template#{'s' unless count == 1} from Meta"
  rescue => e
    redirect_to merchant_whatsapp_templates_path, alert: "Sync failed: #{e.message}"
  end

  def test_template
    template = OwnerWhatsappTemplate.find(params[:id])
    phone = params[:phone].to_s.strip
    return redirect_to merchant_whatsapp_templates_path, alert: "Enter a phone number to test" if phone.blank?

    body_params = test_body_params(template)
    header_parameters = params[:header_url].present? ? [{ "type" => "image", "image" => { "link" => params[:header_url].strip } }] : nil

    meta_id = MerchantWhatsapp::Sender.call(
      template: template, recipient: phone,
      body_parameters: body_params, header_parameters: header_parameters, button_slug: params[:button].presence
    )

    MerchantWhatsappLog.create!(
      shopify_domain: "test", event_key: "test", template_name: template.name,
      recipient: phone, status: "sent", meta_message_id: meta_id, sent_at: Time.current, dry_run: false
    )
    redirect_to merchant_whatsapp_templates_path, notice: "Test sent to #{phone} (#{meta_id})"
  rescue => e
    redirect_to merchant_whatsapp_templates_path, alert: "Test failed: #{e.message}"
  end

  def rule_form
    @rule = params[:id].present? ? MerchantWhatsappRule.find(params[:id]) : new_rule
    @templates = OwnerWhatsappTemplate.order(:name)
    @templates_json = @templates.each_with_object({}) do |t, h|
      positions = t.body_text.to_s.scan(/\{\{(\d+)\}\}/).flatten.map(&:to_i).uniq.sort
      h[t.id.to_s] = {
        body: t.body_text.to_s, header: t.header_text.to_s,
        buttons: t.buttons_list.map { |b| b["text"] || b[:text] },
        positions: positions
      }
    end
    @column_options = (Shop.column_names + Setting.column_names).uniq.sort
    @rule_mapping = @rule.variable_mapping || {}
  end

  def save_rule
    rule = params[:id].present? ? MerchantWhatsappRule.find(params[:id]) : MerchantWhatsappRule.new
    rule.assign_attributes(rule_params)
    rule.conditions = build_conditions
    rule.variable_mapping = build_bindings
    rule.cta_config = parse_json(params[:cta_config_json], {})
    rule.save!
    redirect_to merchant_whatsapp_path, notice: "Rule saved"
  rescue => e
    redirect_to merchant_whatsapp_rule_form_path(id: params[:id]), alert: e.message
  end

  def toggle_rule
    rule = MerchantWhatsappRule.find(params[:id])
    rule.update!(active: !rule.active)
    redirect_to merchant_whatsapp_path, notice: "#{rule.name} #{rule.active? ? 'activated' : 'paused'}"
  end

  def queue
    @rows = ScheduledMerchantWhatsapp.order(created_at: :desc).limit(200).to_a
    @rules = MerchantWhatsappRule.all.index_by(&:id)
  end

  def reports
    @by_rule = MerchantWhatsappLog.real.where("created_at >= ?", 30.days.ago).group(:merchant_whatsapp_rule_id, :status).count
    @rules = MerchantWhatsappRule.all.index_by(&:id)
    @funnel = MerchantWhatsappLog.real.where("created_at >= ?", 30.days.ago).group(:status).count
  end

  def run_scheduler
    MerchantWhatsapp::SchedulerJob.new.perform
    redirect_to merchant_whatsapp_queue_path, notice: "Scheduler run complete"
  end

  private

  def authenticate_admin!
    http_basic_authenticate_or_request_with(
      name: ENV["ADMIN_USER"],
      password: ENV["ADMIN_PASS"]
    )
  end

  def test_body_params(template)
    count = template.body_text.to_s.scan(/\{\{(\d+)\}\}/).flatten.map(&:to_i).max.to_i

    params_list =
      if params[:sample_domain].present?
        shop = Shop.where("shopify_domain ILIKE :q OR primary_domain ILIKE :q", q: "%#{params[:sample_domain].strip}%").first
        shop ? MerchantWhatsapp::VariableResolver.body_parameters(template, shop) : []
      elsif params[:values].present?
        params[:values].split(",").map { |v| { "type" => "text", "text" => v.strip } }
      else
        []
      end

    params_list = params_list.first(count)
    params_list + Array.new([count - params_list.size, 0].max) { { "type" => "text", "text" => "Sample" } }
  end

  def build_conditions
    tables = Array(params[:cond_table])
    columns = Array(params[:cond_column])
    ops = Array(params[:cond_op])
    values = Array(params[:cond_value])
    combiners = Array(params[:cond_combiner])

    columns.each_index.filter_map do |i|
      column = columns[i].to_s.strip
      next if column.blank?

      entry = { "table" => tables[i].presence || "shops", "column" => column, "op" => ops[i].presence || "eq" }
      entry["value"] = values[i] if values[i].present?
      entry["combiner"] = combiners[i].presence || "and"
      entry
    end
  end

  def build_bindings
    raw = params[:binding]
    hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : (raw || {})
    hash.to_h.reject { |_k, v| v.to_s.strip.blank? }
  end

  def new_rule
    MerchantWhatsappRule.new(
      trigger_type: "scheduled", target: "shops",
      date_rule_type: "days_after_installation", date_rule_value: 3,
      date_rule_column: "shops.created_at", category: "recommendation"
    )
  end

  def sender_params
    params.permit(:waba_id, :phone_number_id, :system_user_token, :display_phone_number, :verified_name, :status)
  end

  def template_params
    params.permit(:name, :language, :category, :status, :header_text, :body_text, :description, :meta_template_id)
  end

  def rule_params
    params.permit(:name, :slug, :trigger_type, :event_key, :category, :date_rule_type,
                  :date_rule_value, :date_rule_column, :target, :owner_whatsapp_template_id,
                  :scheduled_hour, :scheduled_minute, :active)
  end

  def parse_json(str, default)
    return default if str.blank?

    JSON.parse(str)
  rescue JSON::ParserError
    default
  end
end
