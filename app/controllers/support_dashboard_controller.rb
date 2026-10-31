class SupportDashboardController < ApplicationController
  SUPPORT_LEAD_QUEUE_PER_PAGE = 10

  before_action :authenticate_admin!
  before_action :require_support_lead_closed_at_column!, only: %i[support_lead_queue close_support_lead reopen_support_lead]

  def index
    @support_lead_queue_count = if support_lead_trackings_closed_at_column_exists?
                                    support_lead_open_queue_scope(2, 7, engineer_mode: :all).count
                                  else
                                    support_lead_queue_scope(2, 7).count
                                  end
    @uninstalled_count = high_value_uninstalled_shops.count
    @callbacks_count = recent_callbacks_scope.count
    @pending_followups_count = FollowUp.where(status: FollowUp::STATUSES[:pending]).count
    @whatsapp_integration_requests_count = WhatsappNumberIntegrationRequest.where(status: ['pending', 'submitted', 'in_progress']).count
    @sms_template_approvals_count = SmsTemplateApproval.where(status: SmsTemplateApproval::STATUSES[:pending]).count
    @calls_target_today = CallTarget.for_date(Date.current).count
    @calls_attempted_today = CallRecord.on_date(Date.current).count
    @last_updated = Time.current
  end

  # Support tool: reprocess the partial-order-edit flow for a single order.
  # GET renders the form; POST runs the reprocess inline and renders the result.
  # Only flow-version-2 shops are processed.
  def reprocess_partial_order
    @domain = params[:shopify_domain].to_s.strip
    @order_id = params[:shopify_order_id].to_s.strip
    @result = run_partial_order_reprocess(@domain, @order_id) if request.post?
  end

  # Support tool: GST tax-invoice generator. Seller details come from
  # GstInvoiceSeller; buyer/invoice details are entered on the page and the
  # PDF is built client-side (jsPDF) — nothing is persisted.
  def gst_invoice; end

  # Aggregated onboarding funnel: distinct shops reaching each QuickOnboardingV2 stage
  # over a recent window, with step-over-step and overall conversion.
  def onboarding_funnel
    # Optional country filter: narrows every funnel/plan/feature figure to shops
    # in that country. The country distribution table below stays unfiltered.
    @country = params[:country].presence

    # Date range: an explicit from/to wins; otherwise fall back to the N-day
    # window (default 30). @days is nil while a custom range is active.
    @from = parse_funnel_date(params[:from])
    @to   = parse_funnel_date(params[:to])
    if @from && @to && @to >= @from
      @days = nil
      range = @from.beginning_of_day..@to.end_of_day
      @range_label = "#{@from.strftime('%d %b %Y')} → #{@to.strftime('%d %b %Y')}"
    else
      @from = @to = nil
      @days = (params[:days].presence&.to_i || 30).clamp(1, 365)
      range = @days.days.ago..Time.current
      @range_label = "last #{@days} days"
    end

    # Shop-age filter on the event's denormalized shop_created_date (the Shopify
    # store's creation date): 'established' = older than 3 months, 'new' = within.
    @shop_age = %w[new established].include?(params[:shop_age]) ? params[:shop_age] : nil
    age_sql = shop_age_sql(@shop_age)

    dated = OnboardingEvent.where(occurred_at: range)

    # country + age are denormalized onto the event (captured at create time), so
    # the funnel needs no shops join and keeps working after a shop uninstalls.
    scope = dated
    scope = scope.where(country_code: @country) if @country
    scope = scope.where(*age_sql) if age_sql
    # { event => distinct shop count } — counted by shopify_domain (survives the
    # shop being destroyed on uninstall, unlike shop_id which gets nulled).
    distinct_shops_by_event = scope.group(:event).distinct.count(:shopify_domain)

    # Distinct shops for a stage = union across its backing events. A single-event
    # stage reads the grouped count; multi-event stages (e.g. theme embed = detected
    # OR skipped) need their own union query since a shop may have emitted more than
    # one of them and we can't just add the per-event counts.
    stage_shop_count = lambda do |events|
      if events.size == 1
        distinct_shops_by_event[events.first].to_i
      else
        scope.where(event: events).distinct.count(:shopify_domain)
      end
    end

    stages = OnboardingEvent::FUNNEL_STAGES
    top = stage_shop_count.call(OnboardingEvent.events_for(stages.first))
    prev_required = top
    @funnel = stages.map do |stage|
      shops = stage_shop_count.call(OnboardingEvent.events_for(stage))
      optional = stage[:optional] == true
      row = {
        key: stage[:key],
        label: stage[:label],
        shops: shops,
        optional: optional,
        pct_of_top: top.positive? ? (shops * 100.0 / top).round(1) : 0.0,
        # Step conversion vs the previous REQUIRED stage — optional side-steps don't
        # reset the baseline, so we never report a bogus drop or a >100% recovery.
        pct_of_prev: prev_required.positive? ? (shops * 100.0 / prev_required).round(1) : 0.0
      }
      prev_required = shops unless optional
      row
    end

    # Theme-embed sub-breakdown: of shops that reached the step, how many had the
    # embed detected vs. skipped it.
    @theme_embed_detail = {
      detected: distinct_shops_by_event["theme_embed_detected"].to_i,
      skipped:  distinct_shops_by_event["theme_embed_skipped"].to_i
    }

    # Feature-selection breakdown: of shops that reached "Selected features", how
    # many turned on each individual feature (booleans live in the event metadata).
    feature_selectors = scope.where(event: "features_selected")
    @feature_selectors_count = feature_selectors.distinct.count(:shopify_domain)
    @feature_breakdown = OnboardingEvent::FEATURE_FLAGS.map do |flag|
      shops = feature_selectors.where("metadata ->> ? = 'true'", flag[:key]).distinct.count(:shopify_domain)
      {
        label: flag[:label],
        shops: shops,
        pct: @feature_selectors_count.positive? ? (shops * 100.0 / @feature_selectors_count).round(1) : 0.0
      }
    end.sort_by { |f| -f[:shops] }

    @started_count = top
    @approved_count = stage_shop_count.call(OnboardingEvent.events_for(stages.last))
    @overall_conversion = top.positive? ? (@approved_count * 100.0 / top).round(1) : 0.0
    @total_events = scope.count

    started_key  = OnboardingEvent::FUNNEL_STAGES.first[:key]
    approved_key = OnboardingEvent::FUNNEL_STAGES.last[:key]

    # Country distribution (started → approved by country) over the FULL window,
    # independent of the country filter so the table always shows every country.
    country_base = dated
    country_base = country_base.where(*age_sql) if age_sql
    started_by_country  = country_base.where(event: started_key).group(:country_code).distinct.count(:shopify_domain)
    approved_by_country = country_base.where(event: approved_key).group(:country_code).distinct.count(:shopify_domain)
    @country_distribution = started_by_country.map do |cc, started|
      approved = approved_by_country[cc].to_i
      {
        country: cc.presence || "—",
        started: started.to_i,
        approved: approved,
        conversion: started.to_i.positive? ? (approved * 100.0 / started.to_i).round(1) : 0.0
      }
    end.sort_by { |r| -r[:started] }
    @countries = @country_distribution.map { |r| r[:country] }.reject { |c| c == "—" }

    # Plan-selection breakdown (respects the country filter via `scope`): of the
    # shops that selected a plan on the subscription page, which plan did they
    # pick (from the plan_selected event metadata)?
    @selected_by_plan = scope.where(event: "plan_selected")
      .group("metadata ->> 'plan'")
      .distinct.count(:shopify_domain)
      .map { |name, count| { plan: name.presence || "—", shops: count } }
      .sort_by { |r| -r[:shops] }

    # Plan-wise approved billing: which plan they activated, read from the
    # billing_approved event metadata so it survives uninstall (no shops join).
    @plan_approved = scope.where(event: approved_key)
      .group("metadata ->> 'plan'")
      .distinct.count(:shopify_domain)
      .map { |name, count| { plan: name.presence || "—", shops: count } }
      .sort_by { |r| -r[:shops] }

    @last_updated = Time.current
  end

  # Heavy query — loaded asynchronously from the index page (see "Show count" on Active stores card).
  def active_stores_count
    count = active_stores_with_plan_and_volume_count
    render json: { count: count }
  rescue StandardError => e
    Rails.logger.error "SupportDashboard#active_stores_count: #{e.class} #{e.message}"
    render json: { error: "Could not load count" }, status: :unprocessable_entity
  end
  
  def verify_setup
    begin
      @shops = verify_setup_shops.page(params[:page]).per(25)
      @total_count = @shops.total_count
      
      respond_to do |format|
        format.html
        format.json { render json: { shops: @shops, total_count: @total_count } }
      end
    rescue => e  
      SlackNotifier::CLIENT.ping(
            text: "Exception in the GetVeirfy Setup- #{e.message} #{e.backtrace}"
          )
      
      # Handle gracefully - show empty results
      @shops = Shop.none.page(1).per(25)
      @total_count = 0
      
      respond_to do |format|
        format.html { render :verify_setup }
        format.json { render json: { shops: [], total_count: 0, error: e.message } }
      end
    end
  end
  
  def churn
    @filters = churn_filters
    missing = churn_schema_missing
    if missing.any?
      return render plain: "Churn dashboard needs pending migrations (missing: #{missing.join(', ')}). " \
                           "Run `rails db:migrate` (20260925120000, 20260925120100) and reload.",
                    status: :service_unavailable
    end

    dashboard = Churn::Dashboard.new(**@filters)

    respond_to do |format|
      format.html do
        @summary = dashboard.summary
        @sync_status = Churn::SyncStatus.current
        @sync_active = Churn::SyncStatus.running?
        @stores = dashboard.stores.page(params[:page]).per(50).load
        render :churn
      end
      format.csv do
        send_data churned_stores_csv(dashboard.stores.limit(5000)),
                  filename: "churned_stores_#{@filters[:from].iso8601}_#{@filters[:to].iso8601}.csv",
                  type: 'text/csv'
      end
    end
  rescue => e
    # Internal, basic-auth page: show the real error instead of the generic 500
    # so it can be fixed without digging through logs.
    message = e.message.to_s
    message = message[0...message.index('#<')] + '#<record>' if message.include?('#<') # never echo record dumps (tokens)
    Rails.logger.error("[SupportDashboard#churn] #{e.class}: #{message.truncate(500)}\n#{Array(e.backtrace).first(20).join("\n")}")
    app_trace = Array(e.backtrace).select { |l| l.include?('/app/') }.first(8)
    render plain: "Churn dashboard error: #{e.class}: #{message.truncate(500)}\n\n#{app_trace.join("\n")}",
           status: :internal_server_error
  end

  # POST /support_dashboard/churn/sync — queue a resync of the last N days.
  def churn_sync
    days = (params[:days].presence || 7).to_i.clamp(1, Churn::ChurnedStoresSyncJob::MAX_DAYS)

    if Churn::SyncStatus.running?
      message = 'A churn sync is already running.'
      return render(json: { ok: false, error: message, status: churn_sync_status_payload }, status: :conflict) if request.xhr?
      return redirect_to(support_dashboard_churn_path(churn_filter_query), alert: message)
    end

    Churn::SyncStatus.queued!(days: days, triggered_by: 'manual')
    Churn::ChurnedStoresSyncJob.perform_async(days, 'manual')

    message = "Sync queued for the last #{days} days."
    return render(json: { ok: true, message: message, status: churn_sync_status_payload }) if request.xhr?
    redirect_to support_dashboard_churn_path(churn_filter_query), notice: message
  end

  # GET /support_dashboard/churn/sync_status — polled by the churn page.
  def churn_sync_status
    render json: churn_sync_status_payload
  end

  # GET /support_dashboard/churn_feedback — exit-survey responses (exit_survey_responses).
  def churn_feedback
    to = parse_filter_date(params[:to]) || Date.current
    from = parse_filter_date(params[:from]) || (to - 30)
    from, to = to, from if from > to
    @feedback_filters = { from: from, to: to, reason: params[:reason].presence_in(Churn::ExitSurvey::REASONS.keys),
                          callback: params[:callback] == '1' }

    period = ExitSurveyResponse.in_period(from.in_time_zone.beginning_of_day, to.in_time_zone.end_of_day)
    @feedback_reason_counts = period.group(:reason).count.sort_by { |_, c| -c }
    @feedback_total = period.count
    @feedback_callbacks = period.wants_callback.count

    scope = period
    scope = scope.where(reason: @feedback_filters[:reason]) if @feedback_filters[:reason]
    scope = scope.wants_callback if @feedback_filters[:callback]
    @feedback = scope.includes(:uninstalled_shop).recent_first.page(params[:page]).per(25)

    snapshots = @feedback.map(&:uninstalled_shop).compact
    @follow_up_targets = load_follow_up_targets(snapshots)
    @snapshot_follow_up_owners = load_snapshot_follow_up_owners(snapshots)
    @feedback_ltv = ChurnedStore.where(uninstalled_shop_id: snapshots.map(&:id)).pluck(:uninstalled_shop_id, :ltv_net).to_h
  rescue => e
    Rails.logger.error("[SupportDashboard#churn_feedback] #{e.class}: #{e.message.to_s.split('#<').first}")
    render plain: "Churn feedback error: #{e.class}: #{e.message.to_s.split('#<').first.truncate(400)}", status: :internal_server_error
  end

  # POST /support_dashboard/risk_customers/load — "Load records": computes the
  # list + revenue header in the background (Churn::RiskCustomersJob).
  def risk_customers_load
    risk = Churn::RiskCustomers.new(**risk_customer_params)
    risk.request_load!
    redirect_to support_dashboard_risk_customers_path(risk.params.merge(params.permit(:q, :sort, :filter).to_h.symbolize_keys))
  end

  # GET /support_dashboard/risk_customers — stores installed in the last 60 days
  # on a paid plan or with more than $5 of usage charges applied. Shows the last
  # loaded result; nothing heavy runs in the request.
  def risk_customers
    @risk = Churn::RiskCustomers.new(**risk_customer_params)
    @risk_building_since = @risk.building_since
    @risk_sort = Churn::RiskCustomers::SORTS.include?(params[:sort]) ? params[:sort] : 'usage'
    @risk_q = params[:q].to_s.strip.downcase.presence
    rows = @risk.rows
    if @risk_q && rows.any?
      matching = Shop.where(id: rows.map(&:shop_id)).where('shopify_domain ILIKE ?', "%#{@risk_q}%").pluck(:id).to_set
      rows = rows.select { |r| matching.include?(r.shop_id) }
    end
    # "Paid, nothing enabled": paid plan and no feature switched on right now
    # (same feature list as the Features column).
    @risk_filter = params[:filter] == 'paid_no_features' ? 'paid_no_features' : nil
    if @risk_filter
      paid_ids = rows.select(&:paid).map(&:shop_id)
      idle = Shop.where(id: paid_ids).includes(:setting).select { |shop| Churn::FeatureSet.labels_for_shop(shop).empty? }.map(&:id).to_set
      rows = rows.select { |r| idle.include?(r.shop_id) }
    end
    rows = case @risk_sort
           when 'newest' then rows.sort_by { |r| -r.shop_id }
           when 'plan' then rows.sort_by { |r| [-r.plan_price.to_f, -r.usage, -r.shop_id] }
           when 'orders' then rows.sort_by { |r| [-r.orders.to_i, -r.usage, -r.shop_id] }
           when 'customers' then rows.sort_by { |r| [-r.customers.to_i, -r.usage, -r.shop_id] }
           else rows.sort_by { |r| [-r.usage, -r.shop_id] }
           end

    respond_to do |format|
      format.html do
        @revenue = @risk.summary
        @risk_counts = @risk.counts
        @risk_rows = Kaminari.paginate_array(rows, total_count: rows.size).page(params[:page]).per(25)
        @risk_shops = Shop.where(id: @risk_rows.map(&:shop_id)).includes(:plan, :setting, follow_ups: :follow_up_comments).index_by(&:id)
        render :risk_customers
      end
      format.csv do
        send_data risk_customers_csv(rows.first(5000)), filename: "risk_customers_#{Date.current.iso8601}.csv", type: 'text/csv'
      end
    end
  rescue => e
    Rails.logger.error("[SupportDashboard#risk_customers] #{e.class}: #{e.message.to_s.split('#<').first}")
    render plain: "Risk customers error: #{e.class}: #{e.message.to_s.split('#<').first.truncate(400)}", status: :internal_server_error
  end

  def risk_customer_params
    { installed_within: params[:installed_within], min_usage: params[:min_usage],
      rev_from: params[:rev_from], rev_to: params[:rev_to] }
  end
  private :risk_customer_params

  def uninstalled
    @uninstalled_age_months = uninstalled_age_months
    full_scope = high_value_uninstalled_shops
    @follow_up_targets = load_follow_up_targets(full_scope)
    @snapshot_follow_up_owners = load_snapshot_follow_up_owners(full_scope)

    filtered_shops = full_scope.select do |uninstalled_shop|
      # Follow-ups live on the shop if one exists for the domain (reinstalled, or a
      # legacy placeholder row), otherwise on an uninstalled_shops snapshot for the
      # domain (shared by duplicate snapshots of the same uninstall).
      owner = @follow_up_targets[uninstalled_shop.shop_domain] ||
              @snapshot_follow_up_owners[uninstalled_shop.shop_domain] ||
              uninstalled_shop
      shop_needs_attention?(owner, contexts: ['Uninstalled Follow-ups'])
    end

    @total_count = filtered_shops.size
    @shops = Kaminari.paginate_array(filtered_shops, total_count: @total_count).page(params[:page]).per(25)
    
    respond_to do |format|
      format.html
      format.json { render json: { shops: @shops, total_count: @total_count } }
    end
  end

  def callbacks
    scope = recent_callbacks_scope
    @follow_up_targets = load_follow_up_targets(scope)

    filtered_requests = scope.select do |request|
      shop = @follow_up_targets[request.shop_domain]
      # Requests with no linked shop have no follow-up record to resolve against,
      # so fall back to the callback request's own status instead of always
      # treating a missing shop as "needs attention".
      shop.present? ? shop_needs_attention?(shop, contexts: ['Callbacks']) : request.status != 'resolved'
    end

    @total_count = filtered_requests.size
    @callback_requests = Kaminari.paginate_array(filtered_requests, total_count: @total_count).page(params[:page]).per(25)
  rescue => e
    Rails.logger.error "Error loading callback requests: #{e.message}"
    SlackNotifier::CLIENT.ping(
      text: "Exception in Support Dashboard Callbacks tab - #{e.message} #{e.backtrace}"
    )
    @callback_requests = Kaminari.paginate_array([], total_count: 0).page(1).per(25)
    @total_count = 0
  end

  # Resolve a callback request directly when it has no linked shop (and therefore
  # no follow-up record to resolve). Used by the "Mark Resolved" action on the
  # Callbacks tab for rows showing "No linked shop found".
  def resolve_callback_request
    callback_request = CallbackRequest.find(params[:id])
    callback_request.update!(status: 'resolved')
    redirect_to support_dashboard_callbacks_path, notice: 'Callback request marked as resolved'
  rescue ActiveRecord::RecordNotFound
    redirect_to support_dashboard_callbacks_path, alert: 'Callback request not found'
  rescue => e
    Rails.logger.error "Error resolving callback request #{params[:id]}: #{e.message}"
    redirect_to support_dashboard_callbacks_path, alert: 'Unable to resolve callback request'
  end

  def whatsapp_integration_requests
    @status_filter = params[:status].presence_in(%w[all pending submitted in_progress completed rejected]) || 'all'
    
    scope = WhatsappNumberIntegrationRequest.order(created_at: :desc)
    
    if @status_filter != 'all'
      scope = scope.where(status: @status_filter)
    end

    @total_count = scope.count
    @whatsapp_requests = scope.page(params[:page]).per(25)
  rescue => e
    Rails.logger.error "Error loading WhatsApp integration requests: #{e.message}"
    SlackNotifier::CLIENT.ping(
      text: "Exception in Support Dashboard WhatsApp Integration Requests tab - #{e.message} #{e.backtrace}"
    )
    @whatsapp_requests = WhatsappNumberIntegrationRequest.none.page(1).per(25)
    @total_count = 0
  end

  def update_whatsapp_integration_status
    request = WhatsappNumberIntegrationRequest.find(params[:id])
    new_status = params[:status]
    status_filter = params[:status_filter].presence || 'all'
    
    unless %w[pending submitted in_progress completed rejected].include?(new_status)
      redirect_to support_dashboard_whatsapp_integration_requests_path(status: status_filter), alert: 'Invalid status'
      return
    end

    if request.update(status: new_status)
      redirect_to support_dashboard_whatsapp_integration_requests_path(status: status_filter), notice: "Request status updated to #{new_status.humanize}"
    else
      redirect_to support_dashboard_whatsapp_integration_requests_path(status: status_filter), alert: 'Failed to update status'
    end
  rescue => e
    Rails.logger.error "Error updating WhatsApp integration request status: #{e.message}"
    redirect_to support_dashboard_whatsapp_integration_requests_path, alert: "Error: #{e.message}"
  end

  def sms_template_approvals
    @status_filter = params[:status].presence_in(%w[all pending approved rejected]) || "pending"
    scope = SmsTemplateApproval.includes(:shop).order(created_at: :desc)
    scope = scope.where(status: @status_filter) unless @status_filter == "all"
    @total_count = scope.count
    @approvals = scope.page(params[:page]).per(25)
  rescue => e
    Rails.logger.error "Error loading SMS template approvals: #{e.message}"
    @approvals = SmsTemplateApproval.none.page(1).per(25)
    @total_count = 0
  end

  def review_sms_template_approval
    approval = SmsTemplateApproval.find(params[:id])
    status = params[:decision].to_s
    reason = params[:reason].to_s

    result = SmsTemplateApprovalService.review(
      approval: approval,
      status: status,
      reviewed_by: "support_admin",
      reason: reason
    )

    if result.ok?
      redirect_to support_dashboard_sms_template_approvals_path(status: params[:status_filter].presence || "pending"), notice: "Template #{status} successfully."
    else
      redirect_to support_dashboard_sms_template_approvals_path(status: params[:status_filter].presence || "pending"), alert: result.errors.join(", ")
    end
  end

  def support_lead_queue
    @shop_age_months, @installed_within_days = normalized_support_lead_filters
    @support_lead_engineer = normalized_support_lead_engineer_param
    @support_lead_shopify_domain = normalized_support_lead_shopify_domain_param
    engineer_mode = support_lead_engineer_filter_mode(@support_lead_engineer)
    open_scope = support_lead_open_queue_scope(@shop_age_months, @installed_within_days, engineer_mode: engineer_mode, shopify_domain_query: @support_lead_shopify_domain)

    @shops = open_scope.includes(:plan, :setting, :support_lead_tracking).order(created_at: :desc).page(params[:page]).per(SUPPORT_LEAD_QUEUE_PER_PAGE)
    shop_ids = @shops.map(&:id)
    SupportLeadTracking.assign_for_shops!(shop_ids)
    SupportLeadTracking.backfill_assigned_engineers!(shop_ids)
    if @shops.any? { |s| s.support_lead_tracking.nil? }
      @shops = open_scope.includes(:plan, :setting, :support_lead_tracking).order(created_at: :desc).page(params[:page]).per(SUPPORT_LEAD_QUEUE_PER_PAGE)
      shop_ids = @shops.map(&:id)
      SupportLeadTracking.backfill_assigned_engineers!(shop_ids)
    end
    @shops.each { |s| s.support_lead_tracking&.reload }
    @total_count = @shops.total_count

    closed_scope = support_lead_closed_queue_scope(@shop_age_months, @installed_within_days, engineer_mode: engineer_mode, shopify_domain_query: @support_lead_shopify_domain)
    @closed_shops = closed_scope.includes(:plan, :setting, :support_lead_tracking)
                                .order(Arel.sql("support_lead_trackings.closed_at DESC NULLS LAST"))
                                .page(params[:closed_page]).per(SUPPORT_LEAD_QUEUE_PER_PAGE)
    @closed_total_count = @closed_shops.total_count
    @closed_shops.each { |s| s.support_lead_tracking&.reload }

    respond_to do |format|
      format.html
      format.json do
        row = lambda do |s|
          {
            id: s.id,
            shopify_domain: s.shopify_domain,
            shop_created_date: s.shop_created_date,
            installed_at: s.created_at&.iso8601,
            plan: s.plan&.name,
            support_lead_tracking: s.support_lead_tracking&.attributes
          }
        end
        render json: {
          shops: @shops.map { |s| row.call(s) },
          closed_shops: @closed_shops.map { |s| row.call(s) },
          total_count: @total_count,
          closed_total_count: @closed_total_count,
          support_lead_engineer: @support_lead_engineer.presence,
          support_lead_shopify_domain: @support_lead_shopify_domain.presence
        }
      end
    end
  rescue StandardError => e
    Rails.logger.error "SupportDashboard#support_lead_queue: #{e.class} #{e.message}\n#{e.backtrace&.first(15)&.join("\n")}"
    @shops = Shop.none.page(1).per(SUPPORT_LEAD_QUEUE_PER_PAGE)
    @closed_shops = Shop.none.page(1).per(SUPPORT_LEAD_QUEUE_PER_PAGE)
    @total_count = 0
    @closed_total_count = 0
    @shop_age_months ||= 2
    @installed_within_days ||= 7
    @support_lead_engineer ||= ""
    @support_lead_shopify_domain ||= ""
    respond_to do |format|
      format.html { render :support_lead_queue }
      format.json { render json: { shops: [], closed_shops: [], total_count: 0, closed_total_count: 0, error: e.message }, status: :unprocessable_entity }
    end
  end

  def update_support_lead_tracking
    shop = Shop.find(params[:shop_id])
    tracking = SupportLeadTracking.find_or_initialize_by(shop_id: shop.id)
    tracking.assigned_engineer = SupportLeadTracking.assign_engineer_for_shop(shop.id) if tracking.assigned_engineer.blank?
    tracking.assign_attributes(support_lead_tracking_params)
    if tracking.save
      redirect_to support_dashboard_support_lead_queue_path(redirect_lead_queue_params), notice: "Updated #{shop.shopify_domain}"
    else
      redirect_back fallback_location: support_dashboard_support_lead_queue_path, alert: tracking.errors.full_messages.to_sentence
    end
  end

  def close_support_lead
    shop = Shop.find(params[:shop_id])
    tracking = SupportLeadTracking.find_by!(shop_id: shop.id)
    if tracking.comment.to_s.strip.blank?
      redirect_to support_dashboard_support_lead_queue_path(redirect_lead_queue_params),
                  alert: "Please add a comment (one per lead) and click Save row before closing."
      return
    end
    if tracking.lead_closed?
      redirect_to support_dashboard_support_lead_queue_path(redirect_lead_queue_params), alert: "Lead is already closed."
      return
    end
    tracking.update_columns(closed_at: Time.current, updated_at: Time.current)
    redirect_to support_dashboard_support_lead_queue_path(redirect_lead_queue_params), notice: "Lead closed: #{shop.shopify_domain}"
  end

  def reopen_support_lead
    shop = Shop.find(params[:shop_id])
    tracking = SupportLeadTracking.find_by!(shop_id: shop.id)
    unless tracking.lead_closed?
      redirect_to support_dashboard_support_lead_queue_path(redirect_lead_queue_params), alert: "Lead is not closed."
      return
    end
    tracking.update_columns(closed_at: nil, updated_at: Time.current)
    redirect_to support_dashboard_support_lead_queue_path(redirect_lead_queue_params), notice: "Lead reopened: #{shop.shopify_domain}"
  end

  def settings_enabled
    @shops = settings_enabled_shops.page(params[:page]).per(25)
    @total_count = @shops.total_count

    respond_to do |format|
      format.html
      format.json { render json: { shops: @shops, total_count: @total_count } }
    end
  rescue => e
    Rails.logger.error "Error in settings_enabled action: #{e.message}"
    SlackNotifier::CLIENT.ping(
      text: "Exception in Support Dashboard Verify Setup tab - #{e.message} #{e.backtrace}"
    )

    @shops = Shop.none.page(1).per(25)
    @total_count = 0

    respond_to do |format|
      format.html { render :settings_enabled }
      format.json { render json: { shops: [], total_count: 0, error: e.message } }
    end
  end

  # Shops that redeemed the free pre-order OTP campaign coupon
  # (PreOrderOtpCampaign). Lists them with when they applied it.
  def otp_campaign
    @coupon_code = PreOrderOtpCampaign.coupon_code
    @campaign_configured = PreOrderOtpCampaign.configured?
    @campaign_active = PreOrderOtpCampaign.active?
    @campaign_start = PreOrderOtpCampaign.start_date
    @campaign_end = PreOrderOtpCampaign.end_date

    @shops = Shop.where.not(otp_campaign_coupon_applied_at: nil)
                 .includes(:plan)
                 .order(otp_campaign_coupon_applied_at: :desc)
                 .page(params[:page]).per(50)
    @total_count = @shops.total_count
  rescue => e
    Rails.logger.error "Error in otp_campaign action: #{e.message}"
    @shops = Shop.none.page(1).per(50)
    @total_count = 0
  end

  # Shops using the COD Form and / or their own (branded) WhatsApp number.
  # ?feature=cod_form | whatsapp_branded | both
  FEATURE_SHOPS_COD_FORM = "shops.id IN (SELECT shop_id FROM cod_form_shop_configs WHERE storefront_mode = 'cod_form')"
  FEATURE_SHOPS_WHATSAPP = "shops.id IN (SELECT shop_id FROM whatsapp_accounts WHERE shop_id IS NOT NULL AND status = 2)"

  def feature_shops
    @feature = params[:feature].presence_in(%w[cod_form whatsapp_branded both]) || "cod_form"
    @counts = {
      "cod_form" => Shop.where(FEATURE_SHOPS_COD_FORM).count,
      "whatsapp_branded" => Shop.where(FEATURE_SHOPS_WHATSAPP).count,
      "both" => Shop.where(FEATURE_SHOPS_COD_FORM).where(FEATURE_SHOPS_WHATSAPP).count
    }
    scope = Shop.includes(:plan, :cod_form_shop_config, :whatsapp_accounts)
    scope = scope.where(FEATURE_SHOPS_COD_FORM) if %w[cod_form both].include?(@feature)
    scope = scope.where(FEATURE_SHOPS_WHATSAPP) if %w[whatsapp_branded both].include?(@feature)
    @shops = scope.order(created_at: :desc).page(params[:page]).per(50)
    @total_count = @shops.total_count
    # Orders placed through the COD Form (form_order_usages, test orders excluded): all time and
    # this calendar month (UTC month; the cap itself uses the shop's time zone).
    shop_ids = @shops.map(&:id)
    usage = CodForm::OrderUsage.where(shop_id: shop_ids)
    @form_orders_total = usage.group(:shop_id).sum(:orders_count)
    @form_orders_month = usage.where(period: Time.current.utc.strftime("%Y-%m")).group(:shop_id).sum(:orders_count)
    @form_orders_all_shops = CodForm::OrderUsage.where("shop_id IN (SELECT shop_id FROM cod_form_shop_configs WHERE storefront_mode = 'cod_form')").sum(:orders_count)
  rescue => e
    Rails.logger.error "Error in feature_shops action: #{e.message}"
    @feature ||= "cod_form"
    @counts ||= {}
    @form_orders_total ||= {}
    @form_orders_month ||= {}
    @form_orders_all_shops ||= 0
    @shops = Shop.none.page(1).per(50)
    @total_count = 0
  end

  def followups
    @status_filter = params[:status].presence_in(%w[pending resolved]) || 'pending'
    scope = FollowUp.includes(:shop, :uninstalled_shop, :follow_up_comments).recent_first
    scope = scope.where(status: FollowUp::STATUSES[@status_filter.to_sym]) if @status_filter.present?

    @follow_ups = scope.page(params[:page]).per(25)
    @total_count = @follow_ups.total_count
  rescue => e
    Rails.logger.error "Error loading pending follow ups: #{e.message}"
    SlackNotifier::CLIENT.ping(
      text: "Exception in Support Dashboard Pending Follow Ups tab - #{e.message} #{e.backtrace}"
    )
    @follow_ups = FollowUp.none.page(1).per(25)
    @total_count = 0
  end

  def paid_followups
    @status_filter = params[:status].presence_in(%w[pending resolved all]) || "pending"

    scope = Shop
      .joins(:plan)
      .where("LOWER(plans.name) <> ?", "free")
      .where("shops.created_at >= ?", 60.days.ago)
      .includes(:plan, :setting, { follow_ups: :follow_up_comments })
      .order(updated_at: :desc)

    if @status_filter != "all"
      desired_status = FollowUp::STATUSES[@status_filter.to_sym]
      scope =
        case @status_filter
        when "pending"
          # "Unresolved" shops should show up in Pending: either no follow-ups yet for this tab,
          # or at least one pending follow-up for this tab.
          scope.where(
            <<~SQL.squish,
              NOT EXISTS (
                SELECT 1 FROM follow_ups fu
                WHERE fu.shop_id = shops.id
                  AND fu.source_tab = 'Paid followups'
              )
              OR EXISTS (
                SELECT 1 FROM follow_ups fu
                WHERE fu.shop_id = shops.id
                  AND fu.source_tab = 'Paid followups'
                  AND fu.status = ?
              )
            SQL
            desired_status
          )
        when "resolved"
          # Resolved means: has at least one resolved follow-up in this tab, and none pending.
          scope.where(
            <<~SQL.squish,
              EXISTS (
                SELECT 1 FROM follow_ups fu
                WHERE fu.shop_id = shops.id
                  AND fu.source_tab = 'Paid followups'
                  AND fu.status = ?
              )
              AND NOT EXISTS (
                SELECT 1 FROM follow_ups fu
                WHERE fu.shop_id = shops.id
                  AND fu.source_tab = 'Paid followups'
                  AND fu.status = ?
              )
            SQL
            desired_status,
            FollowUp::STATUSES[:pending]
          )
        else
          scope
        end
    end

    @shops = scope.page(params[:page]).per(25)
    @total_count = @shops.total_count
  rescue => e
    Rails.logger.error "Error loading paid followups shops: #{e.message}"
    @shops = Shop.none.page(1).per(25)
    @total_count = 0
  end

  def get_crisp_url
    uninstalled_shop = UninstalledShop.find(params[:id])
    
    # Find the corresponding shop record to get crisp URL
    shop = Shop.find_by(shopify_domain: uninstalled_shop.shop_domain)
    
    if shop
      crisp_url = shop.crisp_url
      redirect_to crisp_url, allow_other_host: true
    else
      # Fallback: generate crisp URL manually
      token = Digest::MD5.hexdigest(uninstalled_shop.shop_domain)
      crisp_url = "https://go.crisp.chat/chat/embed/?website_id=#{ENV.fetch("CRISP_WEBSITE_ID", nil)}&user_email=#{uninstalled_shop.email}&user_nickname=#{uninstalled_shop.owner_name}&token_id=#{token}"
      redirect_to crisp_url, allow_other_host: true
    end
  rescue => e
    Rails.logger.error "Error generating crisp URL for shop #{uninstalled_shop&.shop_domain}: #{e.message}"
    
    SlackNotifier::CLIENT.ping(
      text: "Error generating crisp URL for shop #{uninstalled_shop&.shop_domain}: #{e.message}"
    )
    
    redirect_to support_dashboard_uninstalled_path, alert: 'Unable to open chat for this shop'
  end
  
  def update_relationship_manager
    shop = Shop.find(params[:id])
    if shop.update(relationship_manager: params[:relationship_manager])
      redirect_back fallback_location: support_dashboard_verify_setup_path, notice: 'Notes updated successfully'
    else
      redirect_back fallback_location: support_dashboard_verify_setup_path, alert: 'Failed to update Notes'
    end
  end

  def create_follow_up
    shop = Shop.find(params[:id])
    resolve_immediately = ActiveModel::Type::Boolean.new.cast(params[:resolve_immediately])

    attributes = follow_up_params.merge(source_tab: source_tab_param)
    created_by = attributes.delete(:created_by)

    if resolve_immediately
      attributes[:status] = FollowUp::STATUSES[:resolved]
      attributes[:resolved_by] = follow_up_params[:resolved_by]
      attributes[:resolved_source_tab] = source_tab_param
      attributes[:resolved_at] = Time.current
      
      # Append name to resolved_notes if provided
      if created_by.present? && attributes[:resolved_notes].present?
        attributes[:resolved_notes] = "[#{created_by}] #{attributes[:resolved_notes]}"
      end
      
      # Use resolved_notes as notes if notes is empty
      attributes[:notes] = attributes[:notes].presence || attributes[:resolved_notes]
      
      # If notes was empty and we used resolved_notes, ensure name is appended
      if created_by.present? && attributes[:notes] == attributes[:resolved_notes] && !attributes[:notes].start_with?("[#{created_by}]")
        attributes[:notes] = "[#{created_by}] #{attributes[:notes]}"
      end
    else
      # For regular follow-up, append name to notes
      if created_by.present? && attributes[:notes].present?
        attributes[:notes] = "[#{created_by}] #{attributes[:notes]}"
      end
    end

    follow_up = shop.follow_ups.build(attributes)

    if follow_up.save
      refresh_relationship_manager_history(shop)
      message = resolve_immediately ? 'Lead resolved successfully' : 'Follow-up added successfully'
      return render_follow_up_column_fragment(shop, source_tab_param, message) if request.xhr?
      redirect_back fallback_location: support_dashboard_path, notice: message
    else
      return render_follow_up_error(follow_up.errors.full_messages.to_sentence) if request.xhr?
      redirect_back fallback_location: support_dashboard_path, alert: follow_up.errors.full_messages.to_sentence
    end
  end

  def resolve_follow_up
    follow_up = FollowUp.find(params[:id])
    update_params = resolve_follow_up_params.merge(
      status: FollowUp::STATUSES[:resolved],
      resolved_source_tab: resolve_source_tab_param
    )

    if follow_up.update(update_params)
      refresh_relationship_manager_history(follow_up.shop) if follow_up.shop
      return render_follow_up_column_fragment(follow_up.owner, resolve_source_tab_param, 'Follow-up resolved successfully') if request.xhr?
      redirect_back fallback_location: support_dashboard_followups_path, notice: 'Follow-up resolved successfully'
    else
      return render_follow_up_error(follow_up.errors.full_messages.to_sentence) if request.xhr?
      redirect_back fallback_location: support_dashboard_followups_path, alert: follow_up.errors.full_messages.to_sentence
    end
  end

  def create_follow_up_comment
    follow_up = FollowUp.find(params[:follow_up_id])
    comment_params = follow_up_comment_params
    commented_by = comment_params.delete(:commented_by)

    # Append name to comment if provided
    if commented_by.present? && comment_params[:comment].present?
      comment_params[:comment] = "[#{commented_by}] #{comment_params[:comment]}"
    end

    comment = follow_up.follow_up_comments.build(comment_params)

    if comment.save
      if request.xhr?
        source_tab = params[:source_tab].presence || follow_up.source_tab.presence || 'Pending Follow-ups'
        return render_follow_up_column_fragment(follow_up.owner, source_tab, 'Comment added successfully')
      end
      redirect_back fallback_location: support_dashboard_followups_path, notice: 'Comment added successfully'
    else
      return render_follow_up_error(comment.errors.full_messages.to_sentence) if request.xhr?
      redirect_back fallback_location: support_dashboard_followups_path, alert: comment.errors.full_messages.to_sentence
    end
  end

  def new_custom_follow_up
    # Render the form for creating a custom follow-up
  end

  def create_custom_follow_up
    shopify_domain = params[:shopify_domain]&.strip
    
    # Normalize the domain (remove .myshopify.com if present, then add it back)
    if shopify_domain.present?
      shopify_domain = shopify_domain.gsub(/\.myshopify\.com$/, '')
      shopify_domain = "#{shopify_domain}.myshopify.com" unless shopify_domain.include?('.')
    end

    shop = Shop.find_by(shopify_domain: shopify_domain)
    
    unless shop
      flash[:alert] = "Shop with domain '#{shopify_domain}' not found. Please check the domain and try again."
      render :new_custom_follow_up, status: :unprocessable_entity
      return
    end

    resolve_immediately = ActiveModel::Type::Boolean.new.cast(params[:resolve_immediately])
    source_tab = params[:source_tab].presence || 'Custom Follow-up'

    attributes = custom_follow_up_params.merge(source_tab: source_tab)
    created_by = attributes.delete(:created_by)

    if resolve_immediately
      attributes[:status] = FollowUp::STATUSES[:resolved]
      attributes[:resolved_by] = custom_follow_up_params[:resolved_by]
      attributes[:resolved_source_tab] = source_tab
      attributes[:resolved_at] = Time.current
      
      # Append name to resolved_notes if provided
      if created_by.present? && attributes[:resolved_notes].present?
        attributes[:resolved_notes] = "[#{created_by}] #{attributes[:resolved_notes]}"
      end
      
      # Use resolved_notes as notes if notes is empty
      attributes[:notes] = attributes[:notes].presence || attributes[:resolved_notes]
      
      # If notes was empty and we used resolved_notes, ensure name is appended
      if created_by.present? && attributes[:notes] == attributes[:resolved_notes] && !attributes[:notes].start_with?("[#{created_by}]")
        attributes[:notes] = "[#{created_by}] #{attributes[:notes]}"
      end
    else
      # For regular follow-up, append name to notes
      if created_by.present? && attributes[:notes].present?
        attributes[:notes] = "[#{created_by}] #{attributes[:notes]}"
      end
    end

    follow_up = shop.follow_ups.build(attributes)

    if follow_up.save
      refresh_relationship_manager_history(shop)
      message = resolve_immediately ? 'Lead resolved successfully' : 'Custom follow-up added successfully'
      redirect_to support_dashboard_followups_path, notice: message
    else
      flash[:alert] = follow_up.errors.full_messages.to_sentence
      render :new_custom_follow_up, status: :unprocessable_entity
    end
  end
  
  def create_uninstalled_follow_up
    begin
      uninstalled_shop = UninstalledShop.find(params[:id])

      # Attach to the shop if the store has one (reinstalled, or a legacy
      # placeholder that already holds its follow-ups); otherwise to the
      # uninstall snapshot. Never create a placeholder shops row: it fired Shop
      # callbacks with a dead token and counted as a live/reinstalled store.
      owner = Shop.find_by(shopify_domain: uninstalled_shop.shop_domain) ||
              snapshot_follow_up_owner_for(uninstalled_shop.shop_domain) ||
              uninstalled_shop
      
      resolve_immediately = ActiveModel::Type::Boolean.new.cast(params[:resolve_immediately])
      source_tab = params[:source_tab].presence || 'Uninstalled Follow-ups'

      attributes = follow_up_params.merge(source_tab: source_tab)
      created_by = attributes.delete(:created_by)

      if resolve_immediately
        attributes[:status] = FollowUp::STATUSES[:resolved]
        attributes[:resolved_by] = follow_up_params[:resolved_by]
        attributes[:resolved_source_tab] = source_tab
        attributes[:resolved_at] = Time.current
        
        # Append name to resolved_notes if provided
        if created_by.present? && attributes[:resolved_notes].present?
          attributes[:resolved_notes] = "[#{created_by}] #{attributes[:resolved_notes]}"
        end
        
        # Use resolved_notes as notes if notes is empty
        attributes[:notes] = attributes[:notes].presence || attributes[:resolved_notes]
        
        # If notes was empty and we used resolved_notes, ensure name is appended
        if created_by.present? && attributes[:notes] == attributes[:resolved_notes] && !attributes[:notes].start_with?("[#{created_by}]")
          attributes[:notes] = "[#{created_by}] #{attributes[:notes]}"
        end
      else
        # For regular follow-up, append name to notes
        if created_by.present? && attributes[:notes].present?
          attributes[:notes] = "[#{created_by}] #{attributes[:notes]}"
        end
      end

      follow_up = owner.follow_ups.build(attributes)

      if follow_up.save
        refresh_relationship_manager_history(owner) if owner.is_a?(Shop)
        # Also update uninstalled shop notes if provided
        if attributes[:notes].present?
          uninstalled_shop.update(notes: attributes[:notes])
        end
        return render_follow_up_column_fragment(owner, source_tab, 'Follow-up added successfully') if request.xhr?
        redirect_to support_dashboard_uninstalled_path, notice: 'Follow-up added successfully'
      else
        return render_follow_up_error(follow_up.errors.full_messages.to_sentence) if request.xhr?
        redirect_to support_dashboard_uninstalled_path, alert: follow_up.errors.full_messages.to_sentence
      end
    rescue ActionController::ParameterMissing => e
      Rails.logger.error "Parameter missing in create_uninstalled_follow_up: #{e.message}"
      return render_follow_up_error("Missing required fields: #{e.message}") if request.xhr?
      redirect_to support_dashboard_uninstalled_path, alert: "Missing required fields: #{e.message}"
    rescue => e
      Rails.logger.error "Error in create_uninstalled_follow_up: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      return render_follow_up_error("Error creating follow-up: #{e.message}") if request.xhr?
      redirect_to support_dashboard_uninstalled_path, alert: "Error creating follow-up: #{e.message}"
    end
  end
  
  def update_notes
    shop = UninstalledShop.find(params[:id])
    if shop.update(notes: params[:notes])
      redirect_to support_dashboard_uninstalled_path, notice: 'Notes updated successfully'
    else
      redirect_to support_dashboard_uninstalled_path, alert: 'Failed to update notes'
    end
  end
  
  private

  CHURN_DEFAULT_DAYS = 7

  def churn_schema_missing
    conn = ActiveRecord::Base.connection
    missing = %w[churned_stores partner_app_events].reject { |t| conn.table_exists?(t) }
    missing << 'partner_sales.app_id' unless conn.column_exists?(:partner_sales, :app_id)
    missing << 'follow_ups.uninstalled_shop_id' unless conn.column_exists?(:follow_ups, :uninstalled_shop_id)
    missing
  end

  # `active` comes from the lock, not the stored state: a killed worker leaves
  # state "running" behind, and the button must not stay disabled for it.
  def churn_sync_status_payload
    Churn::SyncStatus.current.merge('active' => Churn::SyncStatus.running?)
  end

  CHURN_NUMERIC_PARAMS = Churn::Dashboard::NUMERIC_FILTERS

  def churn_filters
    to = parse_filter_date(params[:to]) || Date.current
    from = parse_filter_date(params[:from]) || (to - CHURN_DEFAULT_DAYS)
    from, to = to, from if from > to
    numeric = CHURN_NUMERIC_PARAMS.index_with do |key|
      value = params[key].presence
      value && value.to_s =~ /\A-?\d+(\.\d+)?\z/ ? value.to_d : nil
    end
    {
      from: from,
      to: to,
      churn_type: params[:churn_type].presence,
      returned: params[:returned].presence,
      sort: params[:sort].presence
    }.merge(numeric)
  end

  def churn_filter_query
    params.permit(:from, :to, :churn_type, :returned, :sort, *CHURN_NUMERIC_PARAMS).to_h
  end

  def parse_filter_date(value)
    Date.parse(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end

  def risk_customers_csv(rows)
    require 'csv'
    shops = Shop.where(id: rows.map(&:shop_id)).includes(:plan, :setting).index_by(&:id)
    CSV.generate do |csv|
      csv << ['Store', 'Owner', 'Email', 'Phone', 'Plan', 'Paid plan', 'Plan price (USD/month)', 'Usage charges applied (USD)',
              'Order confirmations', 'Customers', 'Installed at', 'Shopify store created', 'Features']
      rows.each do |r|
        shop = shops[r.shop_id]
        next unless shop

        csv << [shop.shopify_domain, shop.owner_name.presence || shop.shop_owner, shop.owner_email.presence || shop.customer_email,
                shop.owner_phone, shop.plan&.name, r.paid ? 'yes' : 'no', r.plan_price, r.usage, r.orders, r.customers, shop.created_at&.to_date,
                (Date.parse(shop.shop_created_date.to_s) rescue nil),
                Churn::FeatureSet.labels_for_shop(shop).join(' | ')]
      end
    end
  end

  def churned_stores_csv(stores)
    require 'csv'
    CSV.generate do |csv|
      csv << ['Store', 'Churn type', 'Churned at', 'Plan', 'Plan amount', 'LTV net (USD)', 'Subscription net', 'Usage net',
              'Adjustments', 'Last 30d net', 'Orders processed', 'Days with COD King', 'Store created on', 'Store age (days)',
              'Features', 'Owner', 'Email', 'Phone', 'Uninstall reason', 'Feedback', 'Came back', 'Came back at',
              'Gap (days)', 'Still installed', 'Current plan', 'Orders since return', 'Net since return', 'Prior churns']
      stores.each do |s|
        csv << [s.shopify_domain, s.type_label, s.churned_at&.iso8601, s.plan_name, s.plan_amount, s.ltv_net,
                s.subscription_net, s.usage_net, s.adjustment_net, s.last_30d_net, s.orders_processed, s.tenure_days,
                s.store_created_on, s.store_age_days, Array(s.features).join(' | '), s.owner_name, s.email, s.phone,
                s.uninstall_reason, s.uninstall_feedback, s.returned ? 'yes' : 'no', s.returned_at&.iso8601,
                s.return_gap_days, s.still_installed ? 'yes' : 'no', s.current_plan_name, s.orders_since_return,
                s.net_since_return, s.prior_churn_count]
      end
    end
  end

  # Runs the partial-order-edit reprocess for one order and returns a result hash
  # ({ ok:, message:, mode:, order_confirmation: }) for the view to render.
  # Calls are made inline so the outcome can be reported back to the UI.
  def run_partial_order_reprocess(domain, order_id)
    return { ok: false, message: "Both Shopify domain and Shopify order ID are required." } if domain.blank? || order_id.blank?

    shop = Shop.find_by(shopify_domain: domain)
    return { ok: false, message: "No shop found for domain '#{domain}'." } unless shop
    return { ok: false, message: "Shop '#{domain}' has no settings record." } unless shop.setting

    if shop.setting.partial_payment_flow_version != 2
      return {
        ok: false,
        message: "Shop '#{domain}' is on partial_payment_flow_version=#{shop.setting.partial_payment_flow_version.inspect} (not 2). Skipped — not processed."
      }
    end

    order_confirmation = OrderConfirmation.find_by(shop_id: shop.id, order_id: order_id)

    if order_confirmation
      # Existing record: reprocess the partial edit inline (normal mode, retry_flag = false).
      ShopifyJobs::PartialOrderEditJob.new.perform(shop.id, order_id, nil, false)
      order_confirmation.reload
      {
        ok: true,
        mode: "existing",
        message: "Reprocessed the existing OrderConfirmation inline via PartialOrderEditJob.",
        order_confirmation: order_confirmation
      }
    else
      # The create job decides whether to enqueue PartialOrderEditJob from the
      # order's note_attributes / line-item names — fields the reduced GraphQL
      # projection (OrderGetService) drops, which made every reprocess look
      # non-partial. Use the full REST order (same shape the webhook delivers).
      order_params = fetch_full_order_params(shop, order_id)
      unless order_params.is_a?(Hash) && order_params.present?
        return { ok: false, message: "Could not fetch order #{order_id} from Shopify for '#{domain}'. Verify the order ID belongs to this shop." }
      end

      OrderConfirmationCreateJob.new.perform(order_params, shop.id)
      created = OrderConfirmation.find_by(shop_id: shop.id, order_id: order_id)
      partial = partial_order_params?(order_params)
      {
        ok: true,
        mode: "created",
        message: partial ?
          "No existing OrderConfirmation found. Fetched the full order from Shopify and ran OrderConfirmationCreateJob inline; the order is partial, so PartialOrderEditJob was enqueued and will run in the background." :
          "No existing OrderConfirmation found. Fetched the full order from Shopify and ran OrderConfirmationCreateJob inline. This order carries no partial-payment marker (no 'partial_payment_variants' note attribute and no 'Partial Payment' line item), so PartialOrderEditJob was NOT enqueued.",
        order_confirmation: created
      }
    end
  rescue => e
    Rails.logger.error("[ReprocessPartialOrder] #{e.class}: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
    { ok: false, message: "Error while reprocessing: #{e.message}" }
  end

  def fetch_full_order_params(shop, order_id)
    shop.init_session
    order = ShopifyAPI::Order.find(order_id)
    JSON.parse(order.to_json).to_h
  rescue ActiveResource::ResourceNotFound
    nil
  end

  def partial_order_params?(params)
    has_variant_note =
      Array(params["note_attributes"]).any? do |na|
        na.is_a?(Hash) &&
          na["name"].to_s == "partial_payment_variants" &&
          na["value"].present? &&
          !%w[null NULL].include?(na["value"].to_s)
      end
    return true if has_variant_note

    Array(params["line_items"]).any? do |li|
      li.is_a?(Hash) && li["name"].to_s.downcase.include?("partial payment")
    end
  end

  # WHERE clause for the funnel shop-age filter, compared against the ISO8601
  # string denormalized onto onboarding_events.shop_created_date. [sql, bind]/nil.
  def shop_age_sql(shop_age)
    cutoff = 3.months.ago.iso8601
    case shop_age
    when "established"
      ["shop_created_date IS NOT NULL AND shop_created_date < ?", cutoff]
    when "new"
      ["shop_created_date IS NOT NULL AND shop_created_date >= ?", cutoff]
    end
  end

  # Parse a YYYY-MM-DD value from the funnel date pickers; nil on blank/invalid.
  def parse_funnel_date(val)
    return nil if val.blank?
    Date.iso8601(val.to_s)
  rescue ArgumentError
    begin
      Date.parse(val.to_s)
    rescue ArgumentError
      nil
    end
  end

  def normalized_support_lead_filters
    m = (params[:shop_age_months].presence || 2).to_i
    m = 2 if m < 1
    m = 60 if m > 60
    d = (params[:installed_within_days].presence || 7).to_i
    d = 7 if d < 1
    d = 365 if d > 365
    [m, d]
  end

  # Returns "" (all), "unassigned", or a name from SUPPORT_ENGINEERS.
  def normalized_support_lead_engineer_param
    normalized_support_lead_engineer_param_from(params)
  end

  def normalized_support_lead_engineer_param_from(p)
    raw = p[:support_lead_engineer].to_s.strip
    return "" if raw.blank?
    return "unassigned" if raw == "unassigned"
    return raw if SupportLeadTracking.engineer_pool.include?(raw)

    ""
  end

  def normalized_support_lead_shopify_domain_param
    normalized_support_lead_shopify_domain_param_from(params)
  end

  def normalized_support_lead_shopify_domain_param_from(p)
    p[:support_lead_shopify_domain].to_s.strip.downcase
  end

  def support_lead_engineer_filter_mode(engineer_param)
    return :all if engineer_param.blank?
    return :unassigned if engineer_param == "unassigned"

    engineer_param
  end

  def support_lead_queue_scope(shop_age_months, installed_within_days, shopify_domain_query: "")
    cutoff = shop_age_months.months.ago.iso8601
    installed_since = installed_within_days.days.ago
    scope = Shop.where("shops.created_at >= ?", installed_since)
        .where("shops.shop_created_date IS NOT NULL AND shops.shop_created_date < ?", cutoff)
    if shopify_domain_query.present?
      scope = scope.where("LOWER(shops.shopify_domain) LIKE ?", "%#{Shop.sanitize_sql_like(shopify_domain_query)}%")
    end
    scope
  end

  def support_lead_open_queue_scope(shop_age_months, installed_within_days, engineer_mode: :all, shopify_domain_query: "")
    scope = support_lead_queue_scope(shop_age_months, installed_within_days, shopify_domain_query: shopify_domain_query)
              .left_joins(:support_lead_tracking)
              .where("support_lead_trackings.id IS NULL OR support_lead_trackings.closed_at IS NULL")

    case engineer_mode
    when :all
      scope
    when :unassigned
      scope.where(<<~SQL.squish)
        support_lead_trackings.id IS NULL
        OR support_lead_trackings.assigned_engineer IS NULL
        OR TRIM(support_lead_trackings.assigned_engineer) = ''
      SQL
    else
      scope.where(
        "support_lead_trackings.id IS NOT NULL AND TRIM(support_lead_trackings.assigned_engineer) = ?",
        engineer_mode.to_s.strip
      )
    end
  end

  def support_lead_closed_queue_scope(shop_age_months, installed_within_days, engineer_mode: :all, shopify_domain_query: "")
    scope = support_lead_queue_scope(shop_age_months, installed_within_days, shopify_domain_query: shopify_domain_query)
              .joins(:support_lead_tracking)
              .merge(SupportLeadTracking.lead_closed)

    case engineer_mode
    when :all
      scope
    when :unassigned
      scope.where(<<~SQL.squish)
        support_lead_trackings.assigned_engineer IS NULL
        OR TRIM(support_lead_trackings.assigned_engineer) = ''
      SQL
    else
      scope.where("TRIM(support_lead_trackings.assigned_engineer) = ?", engineer_mode.to_s.strip)
    end
  end

  def redirect_lead_queue_params
    {
      shop_age_months: (params[:shop_age_months].presence || 2).to_i,
      installed_within_days: (params[:installed_within_days].presence || 7).to_i
    }.tap do |h|
      h[:page] = params[:page] if params[:page].present?
      h[:closed_page] = params[:closed_page] if params[:closed_page].present?
      eng = normalized_support_lead_engineer_param_from(params)
      h[:support_lead_engineer] = eng if eng.present?
      dom = normalized_support_lead_shopify_domain_param_from(params)
      h[:support_lead_shopify_domain] = dom if dom.present?
    end
  end

  def support_lead_trackings_closed_at_column_exists?
    SupportLeadTracking.connection.column_exists?(:support_lead_trackings, :closed_at)
  end

  # DB can have closed_at while this process still has a stale column list (migrate without
  # restart, or outdated schema_cache). Sync so update_columns / SELECT include the column.
  def ensure_support_lead_closed_at_in_column_cache!
    return unless support_lead_trackings_closed_at_column_exists?
    return if SupportLeadTracking.column_names.include?("closed_at")

    SupportLeadTracking.reset_column_information
  end

  def require_support_lead_closed_at_column!
    unless support_lead_trackings_closed_at_column_exists?
      redirect_to support_dashboard_path,
                  alert: "Support lead queue needs the closed_at column. Run bin/rails db:migrate on this app’s database, then restart the web server (e.g. Puma)."
      return
    end

    ensure_support_lead_closed_at_in_column_cache!
  end

  def support_lead_tracking_params
    params.fetch(:support_lead_tracking, {}).permit(
      :assigned_engineer,
      :activated,
      :verified_setup,
      :contacted,
      :reminder_1_sent,
      :reminder_2_sent,
      :reminder_3_sent,
      :not_interested,
      :onboarded_to_free_plan,
      :onboarded_to_paid_plan,
      :comment
    )
  end

  # Shops on a plan, with billing (charge_id), a settings row, and >10 order_confirmations in the last 30 days.
  def active_stores_with_plan_and_volume_count
    sql = <<~SQL.squish
      SELECT COUNT(*)
      FROM shops s
      INNER JOIN plans p ON p.id = s.plan_id
      INNER JOIN (
        SELECT shop_id
        FROM order_confirmations
        WHERE created_at >= (CURRENT_DATE - INTERVAL '30 days')
        GROUP BY shop_id
        HAVING COUNT(*) > 10
      ) oc_counts ON oc_counts.shop_id = s.id
      WHERE s.charge_id IS NOT NULL
        AND EXISTS (SELECT 1 FROM settings se WHERE se.shop_id = s.id)
    SQL
    Shop.connection.select_value(sql).to_i
  rescue StandardError => e
    Rails.logger.error "SupportDashboard#active_stores_with_plan_and_volume_count: #{e.class} #{e.message}"
    0
  end

  def authenticate_admin!
    http_basic_authenticate_or_request_with(
      name: ENV.fetch("ADMIN_USER", nil),
      password: ENV.fetch("ADMIN_PASS", nil)
    )
  end
  
  def verify_setup_shops
    # Shops installed within 7 days, shop_created_date older than 3 months, no features enabled, no follow-ups
    begin
      three_months_ago_str = 3.months.ago.iso8601
      seven_days_ago = 7.days.ago
      thirty_days_ago_str = 30.days.ago.to_date.iso8601
      
      Rails.logger.info "=== POTENTIAL LEADS FILTER DEBUG ==="
      Rails.logger.info "Date filters: created_at >= #{seven_days_ago}, shop_created_date < #{three_months_ago_str}, (shop_created_date < #{thirty_days_ago_str} OR customer_count > 100)"
      
      # Stage 1: Initial date filter
      scope = Shop.includes({ follow_ups: :follow_up_comments }, :setting, :plan)
                  .left_outer_joins(:setting)
                  .where(
        "shops.created_at >= ? AND 
         (shops.shop_created_date IS NOT NULL AND shops.shop_created_date < ?) AND
         ((shops.shop_created_date IS NOT NULL AND shops.shop_created_date < ?) OR (shops.customer_count IS NOT NULL AND shops.customer_count > 100))",
        seven_days_ago, three_months_ago_str, thirty_days_ago_str
      ).order('shops.created_at DESC')
      
      count_after_date_filter = scope.count
      Rails.logger.info "Stage 1 - After date filter: #{count_after_date_filter} shops"
      if count_after_date_filter > 0
        sample_shops = scope.limit(5).pluck('shops.id', 'shops.shopify_domain', 'shops.created_at', 'shops.shop_created_date')
        Rails.logger.info "Sample shops after date filter: #{sample_shops.inspect}"
      end

      # Stage 2: No features enabled filter
      # First filter with SQL for simple boolean fields
      no_features_sql_condition = no_features_enabled_sql_condition
      if no_features_sql_condition
        scope = scope.where(no_features_sql_condition)
      end
      
      # Then filter in Ruby using the model method for COD show/hide (handles blank strings correctly)
      shops_after_sql = scope.to_a
      shops_with_no_features = shops_after_sql.select do |shop|
        setting = shop.setting
        next true if setting.nil? # No setting means no features enabled
        
        # Check all features are disabled
        no_sms = setting.sms != true
        no_otp = setting.enable_pre_order_otp != true
        no_partial = setting.partial_payment_enabled != true
        no_cod_show_hide = !setting.is_cod_show_hide_enabled?
        no_cod_fee = setting.cod_fee_enabled != true
        no_shipping_cod_fee = setting.enable_shipping_cod_fees != true
        no_prepaid = setting.prepaid_enabled != true
        no_confirmation_sms = setting.confirmation_sms_enabled != true
        no_confirmation_whatsapp = setting.confirmation_whatsapp != true
        no_fulfilment = setting.enable_fulfilment_message != true
        no_fulfilment_whatsapp = setting.fulfilment_whatsapp != true
        no_abandoned = setting.abandoned_cart_enabled != true
        no_ac_whatsapp = setting.ac_whatsapp != true
        no_verification_link = setting.send_verification_link_only != true
        
        no_sms && no_otp && no_partial && no_cod_show_hide && no_cod_fee && 
        no_shipping_cod_fee && no_prepaid && no_confirmation_sms && no_confirmation_whatsapp &&
        no_fulfilment && no_fulfilment_whatsapp && no_abandoned && no_ac_whatsapp && no_verification_link
      end
      
      # Convert back to ActiveRecord relation for pagination
      shop_ids = shops_with_no_features.map(&:id)
      scope = Shop.where(id: shop_ids).includes({ follow_ups: :follow_up_comments }, :setting, :plan).order('shops.created_at DESC')
      
      count_after_features_filter = scope.count
      Rails.logger.info "Stage 2 - After SQL filter: #{shops_after_sql.count} shops"
      Rails.logger.info "Stage 2 - After Ruby filter (using is_cod_show_hide_enabled?): #{count_after_features_filter} shops"
      
      if count_after_date_filter > count_after_features_filter
        removed_count = count_after_date_filter - count_after_features_filter
        Rails.logger.info "Removed #{removed_count} shops due to features being enabled"
      end

      # Stage 3: Follow-up filter
      count_before_followup_filter = scope.count
      scope = scope.where(
        <<~SQL.squish
          NOT EXISTS (
            SELECT 1 FROM follow_ups fu
            WHERE fu.shop_id = shops.id AND fu.source_tab = 'Potential Leads'
          )
        SQL
      )
      count_after_followup_filter = scope.count
      Rails.logger.info "Stage 3 - Before follow-up filter: #{count_before_followup_filter} shops"
      Rails.logger.info "Stage 3 - After follow-up filter: #{count_after_followup_filter} shops"
      
      if count_before_followup_filter > count_after_followup_filter
        removed_count = count_before_followup_filter - count_after_followup_filter
        Rails.logger.info "Removed #{removed_count} shops due to existing follow-ups in 'Potential Leads' context"
        
        # Check which shops have follow-ups
        shops_with_followups = Shop.includes({ follow_ups: :follow_up_comments })
                                  .left_outer_joins(:setting)
                                  .where(
          "shops.created_at >= ? AND 
           (shops.shop_created_date IS NOT NULL AND shops.shop_created_date < ?)",
          seven_days_ago, three_months_ago_str
        )
        if no_features_sql_condition
          shops_with_followups = shops_with_followups.where(no_features_sql_condition)
        end
        shops_with_followups = shops_with_followups.where(
          "EXISTS (
            SELECT 1 FROM follow_ups fu
            WHERE fu.shop_id = shops.id AND fu.source_tab = 'Potential Leads'
          )"
        ).limit(5)
        
        shops_with_followups.each do |shop|
          followups = shop.follow_ups.where(source_tab: 'Potential Leads')
          Rails.logger.info "Shop #{shop.shopify_domain} (ID: #{shop.id}) has #{followups.count} follow-up(s) in 'Potential Leads': #{followups.pluck(:id, :status, :source_tab).inspect}"
        end
      end
      
      Rails.logger.info "=== FINAL RESULT: #{count_after_followup_filter} shops ==="
      
      scope
    rescue => e
      Rails.logger.error "Error in verify_setup_shops: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      Shop.none # Return empty relation if query fails
    end
  end
  
  MIN_HIGH_VALUE_ORDERS = 30
  MIN_HIGH_VALUE_CUSTOMERS = 100
  DEFAULT_UNINSTALLED_AGE_MONTHS = 1

  def uninstalled_age_months
    (params[:uninstalled_age_months].presence || DEFAULT_UNINSTALLED_AGE_MONTHS).to_i.clamp(0, 60)
  end

  # Uninstalled shops worth following up: a meaningful order count, OR a sizeable
  # customer base (>100), OR an established store (older than N months — N is
  # configurable via ?uninstalled_age_months). Excludes ones already noted, and
  # limited to recent uninstalls.
  def high_value_uninstalled_shops
    age_cutoff = uninstalled_age_months.months.ago.iso8601

    UninstalledShop.where(
      <<~SQL.squish,
        (
          (order_count IS NOT NULL AND order_count ~ '^[0-9]+$' AND CAST(order_count AS INTEGER) >= :min_orders)
          OR (customer_count IS NOT NULL AND customer_count >= :min_customers)
          OR (shopify_created_on IS NOT NULL AND shopify_created_on <> '' AND shopify_created_on < :age_cutoff)
        )
        AND (notes IS NULL OR notes = '')
        AND created_at >= :recent
      SQL
      min_orders: MIN_HIGH_VALUE_ORDERS,
      min_customers: MIN_HIGH_VALUE_CUSTOMERS,
      age_cutoff: age_cutoff,
      recent: 7.days.ago
    ).order(created_at: :desc)
  rescue => e
    Rails.logger.error "Error in high_value_uninstalled_shops: #{e.message}"
    UninstalledShop.none # Return empty relation if query fails
  end

  def settings_enabled_shops
    settings_enabled_scope
  rescue => e
    Rails.logger.error "Error in settings_enabled_shops: #{e.message}"
    Shop.none
  end

  def settings_enabled_scope
    condition = settings_enabled_condition
    return Shop.none unless condition

    thirty_days_ago_str = 30.days.ago.to_date.iso8601

    scope = Shop.includes(:setting, { follow_ups: :follow_up_comments }, :plan)
        .joins(:setting)
        .where(condition)
        .where(
          "(shops.shop_created_date IS NOT NULL AND shops.shop_created_date < ?) OR (shops.customer_count IS NOT NULL AND shops.customer_count > 100)",
          thirty_days_ago_str
        )
        .where('shops.created_at >= ?', 15.days.ago)
        .order(created_at: :desc)

    apply_follow_up_visibility_filter(scope, contexts: ['Verify Setup'])
  end

  def settings_enabled_condition
    settings_table = Setting.arel_table

    feature_conditions = [
      settings_table[:enable_pre_order_otp].eq(true),
      settings_table[:partial_payment_enabled].eq(true),
      settings_table[:enable_shipping_cod_fees].eq(true),
      cod_show_hide_condition(settings_table)
    ].compact

    return nil if feature_conditions.empty?

    feature_conditions.reduce { |memo, condition| memo.or(condition) }
  end

  def no_features_enabled_sql_condition
    settings_table = Setting.arel_table

    # Build conditions for each feature being disabled (all must be false/null)
    # Use IS NOT TRUE to handle NULL values correctly in PostgreSQL
    disabled_conditions = []

    # OTP: both sms and enable_pre_order_otp must be false/null
    disabled_conditions << settings_table[:sms].not_eq(true).or(settings_table[:sms].eq(nil))
    disabled_conditions << settings_table[:enable_pre_order_otp].not_eq(true).or(settings_table[:enable_pre_order_otp].eq(nil))

    # Partial payment
    disabled_conditions << settings_table[:partial_payment_enabled].not_eq(true).or(settings_table[:partial_payment_enabled].eq(nil))

    # Note: COD show/hide is checked in Ruby using setting.is_cod_show_hide_enabled?
    # This handles blank strings correctly (present? method)

    # COD fees: both must be false/null
    disabled_conditions << settings_table[:cod_fee_enabled].not_eq(true).or(settings_table[:cod_fee_enabled].eq(nil))
    disabled_conditions << settings_table[:enable_shipping_cod_fees].not_eq(true).or(settings_table[:enable_shipping_cod_fees].eq(nil))

    # Prepaid
    disabled_conditions << settings_table[:prepaid_enabled].not_eq(true).or(settings_table[:prepaid_enabled].eq(nil))

    # Confirmation message: both must be false/null
    disabled_conditions << settings_table[:confirmation_sms_enabled].not_eq(true).or(settings_table[:confirmation_sms_enabled].eq(nil))
    disabled_conditions << settings_table[:confirmation_whatsapp].not_eq(true).or(settings_table[:confirmation_whatsapp].eq(nil))

    # Fulfilment message: both must be false/null
    disabled_conditions << settings_table[:enable_fulfilment_message].not_eq(true).or(settings_table[:enable_fulfilment_message].eq(nil))
    disabled_conditions << settings_table[:fulfilment_whatsapp].not_eq(true).or(settings_table[:fulfilment_whatsapp].eq(nil))

    # Abandoned cart: both must be false/null
    disabled_conditions << settings_table[:abandoned_cart_enabled].not_eq(true).or(settings_table[:abandoned_cart_enabled].eq(nil))
    disabled_conditions << settings_table[:ac_whatsapp].not_eq(true).or(settings_table[:ac_whatsapp].eq(nil))

    # COD verification WhatsApp
    disabled_conditions << settings_table[:send_verification_link_only].not_eq(true).or(settings_table[:send_verification_link_only].eq(nil))

    # Return condition: either no setting exists, OR all features are disabled
    if disabled_conditions.empty?
      return settings_table[:id].eq(nil)
    end

    all_disabled_condition = disabled_conditions.compact.reduce do |memo, condition|
      memo.and(condition)
    end

    settings_table[:id].eq(nil).or(all_disabled_condition)
  end

  def follow_up_params
    params.require(:follow_up).permit(:notes, :resolved_notes, :resolved_by, :created_by)
  end

  # AJAX responses for the follow-up forms: return the re-rendered follow-up
  # column for one shop so the page can swap it in place instead of reloading.
  def render_follow_up_column_fragment(shop, source_tab, message)
    shop.follow_ups.reset if shop.association(:follow_ups).loaded?
    html = render_to_string(
      partial: 'support_dashboard/follow_up_column',
      locals: { shop: shop, source_tab: source_tab },
      layout: false,
      formats: [:html]
    )
    render json: { success: true, message: message, html: html }
  end

  def render_follow_up_error(message)
    render json: { success: false, error: message }, status: :unprocessable_entity
  end

  def resolve_follow_up_params
    params.require(:follow_up).permit(:resolved_notes, :resolved_by)
  end

  def follow_up_comment_params
    params.require(:follow_up_comment).permit(:comment, :commented_by)
  end

  def custom_follow_up_params
    params.require(:follow_up).permit(:notes, :resolved_notes, :resolved_by, :created_by)
  end

  def source_tab_param
    params[:source_tab].presence || 'Unknown'
  end

  def resolve_source_tab_param
    params[:resolved_source_tab].presence || 'Pending Follow-ups'
  end

  def refresh_relationship_manager_history(shop)
    history_lines = shop.follow_ups.recent_first.flat_map do |follow_up|
      lines = [format_follow_up_history_line(follow_up.created_at, follow_up.source_tab, "Follow-up", follow_up.notes)]

      if follow_up.resolved?
        lines << format_follow_up_history_line(follow_up.resolved_at, follow_up.resolved_source_tab, "Resolved", follow_up.resolved_notes)
      end

      lines
    end

    shop.update_columns(relationship_manager: history_lines.join("\n"))
  end

  def format_follow_up_history_line(timestamp, tab, action, text)
    formatted_time = timestamp.present? ? timestamp.strftime("%b %d, %Y %I:%M %p") : Time.current.strftime("%b %d, %Y %I:%M %p")
    "[#{formatted_time}] (#{tab}) #{action}: #{text}"
  end

  def apply_follow_up_visibility_filter(scope, contexts: nil)
    pending_status = FollowUp::STATUSES[:pending]
    params = { pending_status: pending_status }
    context_clause = ""

    if contexts.present?
      context_clause = "AND fu.source_tab IN (:contexts)"
      params[:contexts] = contexts
    end

    scope.where(
      <<~SQL.squish, params
        NOT EXISTS (
          SELECT 1 FROM follow_ups fu
          WHERE fu.shop_id = shops.id #{context_clause}
        )
        OR EXISTS (
          SELECT 1 FROM follow_ups fu
          WHERE fu.shop_id = shops.id #{context_clause}
            AND fu.status = :pending_status
        )
      SQL
    )
  end

  # domain => the uninstalled_shops row that holds that domain's follow-ups.
  def load_snapshot_follow_up_owners(uninstalled_scope)
    domains = uninstalled_scope.map(&:shop_domain).compact.uniq
    return {} if domains.empty?

    UninstalledShop.where(shop_domain: domains)
                   .where(id: FollowUp.where.not(uninstalled_shop_id: nil).select(:uninstalled_shop_id))
                   .includes(follow_ups: :follow_up_comments)
                   .order(created_at: :desc)
                   .each_with_object({}) { |row, map| map[row.shop_domain] ||= row }
  end

  def snapshot_follow_up_owner_for(domain)
    UninstalledShop.where(shop_domain: domain)
                   .where(id: FollowUp.where.not(uninstalled_shop_id: nil).select(:uninstalled_shop_id))
                   .order(created_at: :desc).first
  end

  def load_follow_up_targets(uninstalled_scope)
    domains = uninstalled_scope.map(&:shop_domain).compact
    shops = Shop.includes({ follow_ups: :follow_up_comments }).where(shopify_domain: domains)
    shops.index_by(&:shopify_domain)
  end

  def recent_callbacks_scope
    CallbackRequest.where('created_at >= ?', 7.days.ago).order(created_at: :desc)
  end

  def shop_needs_attention?(shop, contexts: nil)
    return true if shop.nil?

    followups = if contexts.present?
                  shop.follow_ups.select { |f| contexts.include?(f.source_tab) }
                else
                  shop.follow_ups
                end

    followups.empty? || followups.any?(&:pending?)
  end

  def cod_show_hide_condition(settings_table)
    string_columns = %i[
      hide_delivery_method
      selected_countries
      selected_zips
      selected_product_ids
      phone_numbers
      excluded_zips
      excluded_shipping_methods
      show_provinces
      hide_provinces
      hide_product_variant_ids
      show_product_ids
      email_addresses
      hide_vendors
      show_vendors
      selected_collection_ids
      excluded_collection_ids
    ]

    integer_columns = %i[
      min_cart_total
      max_cart_total
      hide_discount_total
    ]

    boolean_columns = %i[
      hide_gift_cards
    ]

    conditions = []

    string_columns.each do |column|
      attribute = settings_table[column]
      conditions << attribute.not_eq(nil).and(attribute.not_eq(''))
    end

    integer_columns.each do |column|
      attribute = settings_table[column]
      conditions << attribute.not_eq(nil).and(attribute.not_eq(0))
    end

    boolean_columns.each do |column|
      attribute = settings_table[column]
      conditions << attribute.eq(true)
    end

    return nil if conditions.empty?

    conditions.reduce { |memo, condition| memo.or(condition) }
  end
  
  # Use the same authentication as your admin controllers

end
