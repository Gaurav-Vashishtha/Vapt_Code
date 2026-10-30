# frozen_string_literal: true

module CustomBranded
  class PortalController < BaseController
    layout false

    TEMPLATES_PER_PAGE = 20

    # Merchant-facing page: connect a WhatsApp number, see its status —
    # nothing else. ParcelX registers the brand via POST /api/v1/cb/brands and
    # 302s the merchant's browser to the signed connect_url it gets back.
    def connect
      @accounts = @client.whatsapp_accounts.order(is_default: :desc, id: :asc)
      assign_branding
      @meta_app_id = ENV['META_APP_ID']
      @meta_config_id = ENV['META_CONFIG_ID']
      @meta_graph_api_version = ENV['META_GRAPH_API_VERSION'].presence || 'v22.0'
    end

    # Brand page: connected numbers (view + connect more — a brand can have
    # several) and a read-only, paginated view of the brand's templates.
    # Everything operational (keys, webhooks, sends, docs) lives on the
    # ParcelX panel (/cb-stats) or the API.
    def show
      assign_branding
      @accounts = @client.whatsapp_accounts.order(is_default: :desc, id: :asc)
      @meta_app_id = ENV['META_APP_ID']
      @meta_config_id = ENV['META_CONFIG_ID']
      @meta_graph_api_version = ENV['META_GRAPH_API_VERSION'].presence || 'v22.0'

      @page = [params[:page].to_i, 1].max
      scope = @client.whatsapp_templates.includes(:whatsapp_account, :custom_branded_template_event).order(:name)
      @total = scope.count
      @total_pages = [(@total.to_f / TEMPLATES_PER_PAGE).ceil, 1].max
      @page = @total_pages if @page > @total_pages
      @templates = scope.offset((@page - 1) * TEMPLATES_PER_PAGE).limit(TEMPLATES_PER_PAGE)
      @template_names = @client.whatsapp_templates.pluck(:name).uniq
    end

    private

    def assign_branding
      @brand_logo = ENV['CB_BRAND'].presence
      @brand_name = ENV['CB_BRAND_NAME'].presence || 'ParcelX WhatsApp Automation Panel'
    end
  end
end
