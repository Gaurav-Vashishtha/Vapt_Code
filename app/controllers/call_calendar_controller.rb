# frozen_string_literal: true

class CallCalendarController < ApplicationController
  before_action :authenticate_admin!

  DONE_STATUSES = %w[attempted skipped].freeze

  # Human labels for the feature-adoption toggles shown in each row's detail
  # panel. Keys are Setting columns; the canonical feature set is
  # Setting::CHURN_ADOPTION_COLUMNS, so new columns there are picked up
  # automatically (falling back to a humanized column name).
  FEATURE_LABELS = {
    "sms" => "SMS",
    "confirmation_sms_enabled" => "COD confirmation SMS",
    "confirmation_whatsapp" => "COD confirmation WhatsApp",
    "fulfilment_whatsapp" => "Fulfilment WhatsApp",
    "ac_whatsapp" => "Abandoned cart WhatsApp",
    "abandoned_cart_enabled" => "Abandoned cart",
    "cod_fee_enabled" => "COD fee",
    "prepaid_enabled" => "Prepaid discount",
    "partial_payment_enabled" => "Partial payment",
    "enable_pre_order_otp" => "Pre-order OTP",
    "first_purchase_whatsapp_enabled" => "First-purchase WhatsApp",
    "enable_fulfilment_message" => "Fulfilment message"
  }.freeze

  # Column layout of the "Default process Allocations" template the calling
  # tool imports; only the first four are filled, the rest must still be
  # present as headers or the import is rejected.
  EXPORT_HEADERS = [
    "Name", "Mobile Number", "Email", "Company Name", "Street", "Address", "City", "State",
    "Country", "Pincode", "Alternate Name", "Alternate Phone", "Priority", "Assign To (Mobile No)",
    "Notes", "Pickup Date", "Delivery Date", "Pick up location", "Drop location address",
    "Type of Product", "No.of Items", "Consignement weigth (Approx in kgs)", "Vehicle requirement",
    "Special Instructions", "Source", "Status", "Non contact reason", "Non Contact Followup On"
  ].freeze

  def index
    @date = parse_date(params[:date]) || Date.current
    @tab = %w[todo done callbacks demos stats].include?(params[:tab]) ? params[:tab] : "todo"
    @query = params[:q].to_s.strip
    @engineers = SupportCalls::DayOwner.pool

    all_targets = CallTarget.for_date(@date).ranked.to_a
    @day_owner = all_targets.first&.assigned_engineer || SupportCalls::DayOwner.for_date(@date)
    @report = SupportCalls::DailyReport.new(@date).to_h
    @todo_count = all_targets.count { |t| t.status == "pending" }
    @done_count = all_targets.count { |t| DONE_STATUSES.include?(t.status) }
    @support_callbacks_count = CallReminder.open_reminders.for_team("support").count
    @sales_callbacks_count = CallReminder.open_reminders.for_team("sales").count
    @callbacks_count = @support_callbacks_count + @sales_callbacks_count
    @demos_count = CallDemo.count

    # Paginate 75 at a time so long queues load a page at a time.
    @per = 75
    @page = [params[:page].to_i, 1].max
    offset = (@page - 1) * @per
    @total_visible = 0
    paged = []

    if @tab == "callbacks"
      # Callbacks are split by owning team; legacy (null-team) rows show under
      # Support. Default to the Support list.
      @callback_team = CallReminder::TEAMS.include?(params[:cb_team]) ? params[:cb_team] : "support"
      all_callbacks = CallReminder.open_reminders.for_team(@callback_team).order(:due_on, :created_at).to_a
      @total_visible = all_callbacks.size
      paged = all_callbacks[offset, @per] || []
      @callback_rows = build_callback_rows(paged)
    elsif @tab == "demos"
      # Demos, newest first, optionally filtered by status.
      @demo_status = CallDemo::STATUSES.include?(params[:demo_status]) ? params[:demo_status] : nil
      scope = @demo_status ? CallDemo.with_status(@demo_status) : CallDemo.all
      @demo_status_counts = CallDemo.group(:status).count
      @demo_status_chips = CallDemo::STATUSES.select do |st|
        CallDemo::SELECTABLE_STATUSES.include?(st) || @demo_status == st || (@demo_status_counts[st] || 0).positive?
      end
      all_demos = scope.upcoming_first.to_a
      @total_visible = all_demos.size
      paged = all_demos[offset, @per] || []
      @demo_rows = build_demo_rows(paged)
    elsif @tab == "stats"
      @stats_from = parse_date(params[:from]) || Date.current.beginning_of_month
      @stats_to = parse_date(params[:to]) || Date.current
      @stats = compute_stats(@stats_from, @stats_to)
    else
      visible = if @tab == "done"
                  all_targets.select { |t| DONE_STATUSES.include?(t.status) }
                else
                  all_targets.select { |t| t.status == "pending" }
                end
      @total_visible = visible.size
      paged = visible[offset, @per] || []
      @rows = build_rows(paged)
    end

    @range_start = @total_visible.zero? ? 0 : offset + 1
    @range_end = offset + paged.size
    @has_prev = @page > 1
    @has_more = @total_visible > (offset + paged.size)

    @search_row = @query.present? ? build_search_row(@query) : nil
    @is_sunday = @date.sunday?
  end

  def calendar
    @month = (parse_date("#{params[:month]}-01") || Date.current).beginning_of_month
    start_date = @month.beginning_of_month
    end_date = @month.end_of_month
    @reminders_by_day = CallReminder.for_month(start_date, end_date).order(:due_on).group_by(&:due_on)
    @counts_by_day = CallRecord.where(called_at: start_date.beginning_of_day..end_date.end_of_day)
                               .group("DATE(called_at)").count
  end

  def export
    date = parse_date(params[:date]) || Date.current
    targets = CallTarget.for_date(date).ranked.to_a
    targets = targets.select { |t| t.status == "pending" } if params[:tab] == "todo"
    targets = targets.select { |t| DONE_STATUSES.include?(t.status) } if params[:tab] == "done"

    # Export only the page currently on screen, mirroring the 75-per-page slice
    # used by #index, so a 300-row queue downloads 75 rows, not all 300.
    per = 75
    page = [params[:page].to_i, 1].max
    targets = targets[(page - 1) * per, per] || []

    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Sheet1") do |sheet|
      sheet.add_row EXPORT_HEADERS
      targets.each do |t|
        sheet.add_row(
          [t.contact_name, t.contact_phone, t.contact_email, t.shopify_domain] + Array.new(EXPORT_HEADERS.size - 4),
          types: Array.new(EXPORT_HEADERS.size, :string)
        )
      end
    end

    send_data package.to_stream.read,
              filename: "call_calendar_#{date.strftime('%Y-%m-%d')}#{params[:tab].present? ? "_#{params[:tab]}" : ''}_page#{page}.xlsx",
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
              disposition: "attachment"
  end

  def log_outcome
    domain = param_domain
    outcome = params[:outcome].to_s
    return redirect_back_to_day("Invalid outcome") unless CallRecord::OUTCOMES.include?(outcome)

    agent = param_agent
    # For a "Demo scheduled" outcome, capture the demo date & time so it can be
    # listed and sorted on the Demos tab. Stored in metadata to avoid a schema change.
    demo_at = outcome == "demo_scheduled" ? parse_demo_at(params[:demo_at]) : nil
    record = CallRecord.create!(
      shopify_domain: domain,
      shop_id: params[:shop_id].presence,
      call_target_id: params[:call_target_id].presence,
      segment: params[:segment].presence,
      outcome: outcome,
      agent_name: agent,
      notes: params[:notes].presence,
      cps_at_call: params[:cps].presence,
      called_at: Time.current,
      metadata: demo_at ? { "demo_at" => demo_at.iso8601 } : {}
    )
    CallEvent.record!(domain: domain, type: "outcome_logged", agent: agent, shop_id: params[:shop_id].presence,
                      payload: { outcome: outcome, label: CallRecord::OUTCOME_LABELS[outcome], notes: params[:notes],
                                 demo_at: demo_at&.strftime("%d %b %Y, %-I:%M %p") })
    # A "Demo scheduled" outcome also opens a first-class demo on the Demos tab.
    if outcome == "demo_scheduled"
      CallDemo.create!(shopify_domain: domain, shop_id: params[:shop_id].presence, scheduled_at: demo_at,
                       owner: agent, status: "scheduled", notes: params[:notes].presence,
                       source_call_record_id: record.id, created_by: agent)
    end
    apply_outcome_side_effects(domain, outcome, agent)
    record_attempt(domain, params[:call_target_id].presence, params[:segment].presence)
    redirect_back_to_day("Logged: #{CallRecord::OUTCOME_LABELS[outcome]} for #{domain}")
  end

  def add_comment
    domain = param_domain
    comment = params[:comment].to_s.strip
    return redirect_back_to_day("Comment was empty") if comment.blank?

    CallEvent.record!(domain: domain, type: "comment_added", agent: param_agent, shop_id: params[:shop_id].presence,
                      payload: { comment: comment })
    redirect_back_to_day("Comment added")
  end

  def set_reminder
    domain = param_domain
    due = parse_date(params[:due_on])
    return redirect_back_to_day("Pick a valid callback date") unless due

    due += 1 if due.sunday?
    team = CallReminder.normalize_team(params[:team])
    CallReminder.create!(shopify_domain: domain, shop_id: params[:shop_id].presence, due_on: due,
                         note: params[:note].presence, created_by: param_agent, status: "open", team: team)
    CallEvent.record!(domain: domain, type: "reminder_set", agent: param_agent, shop_id: params[:shop_id].presence,
                      payload: { due_on: due.to_s, note: params[:note], team: team })
    redirect_back_to_day("#{team.capitalize} callback set for #{due.strftime('%d %b %Y')}")
  end

  def complete_reminder
    reminder = CallReminder.find(params[:id])
    agent = param_agent
    outcome = params[:outcome].to_s.presence
    outcome = nil unless outcome && CallRecord::OUTCOMES.include?(outcome)
    reminder.update!(status: "done", outcome: outcome, completed_by: agent, completed_at: Time.current)
    CallEvent.record!(domain: reminder.shopify_domain, type: "reminder_completed", agent: agent,
                      payload: { reminder_id: reminder.id, outcome: outcome,
                                 label: outcome ? CallRecord::OUTCOME_LABELS[outcome] : nil })
    label = outcome ? " (#{CallRecord::OUTCOME_LABELS[outcome]})" : ""
    redirect_back_to_day("Callback marked done#{label}")
  end

  def create_demo
    domain = param_domain
    return redirect_to_demos("Enter a shop domain for the demo") if domain.blank?

    shop = Shop.where("shopify_domain ILIKE :q OR primary_domain ILIKE :q", q: domain).first
    CallDemo.create!(
      shopify_domain: shop&.shopify_domain || domain,
      shop_id: shop&.id,
      scheduled_at: parse_demo_at(params[:scheduled_at]),
      owner: params[:owner].presence,
      status: "scheduled",
      notes: params[:notes].presence,
      created_by: param_agent
    )
    CallEvent.record!(domain: shop&.shopify_domain || domain, type: "demo_created", agent: param_agent,
                      payload: { owner: params[:owner], scheduled_at: params[:scheduled_at] })
    redirect_to_demos("Demo created for #{shop&.shopify_domain || domain}")
  rescue => e
    Rails.logger.error("[CallCalendar create_demo] #{e.class}: #{e.message}")
    redirect_to_demos("Couldn't create demo: #{e.message}")
  end

  def update_demo
    demo = CallDemo.find(params[:id])
    previous_at = demo.scheduled_at
    rescheduled_at = parse_demo_at(params[:scheduled_at])
    status = resolved_demo_status(params[:status], rescheduled_at, demo.status)
    demo.update!(
      status: status,
      owner: params[:owner].presence || demo.owner,
      scheduled_at: rescheduled_at || demo.scheduled_at
    )
    CallEvent.record!(domain: demo.shopify_domain, type: "demo_updated", agent: param_agent,
                      payload: { status: status, label: demo.status_label, owner: demo.owner })
    if rescheduled_at.present? && rescheduled_at != previous_at
      CallEvent.record!(domain: demo.shopify_domain, type: "demo_rescheduled", agent: param_agent,
                        payload: { from: previous_at&.iso8601, to: rescheduled_at.iso8601,
                                   from_label: previous_at&.strftime("%d %b %Y, %-I:%M %p"),
                                   to_label: rescheduled_at.strftime("%d %b %Y, %-I:%M %p") })
      return redirect_to_demos(
        "Demo for #{demo.shopify_domain} moved to #{rescheduled_at.strftime('%d %b %Y, %-I:%M %p')}"
      )
    end
    redirect_to_demos("Demo for #{demo.shopify_domain} → #{demo.status_label}")
  end

  def suppress
    domain = param_domain
    reason = params[:reason].to_s
    return redirect_back_to_day("Invalid suppression reason") unless CallSuppression::REASONS.include?(reason)

    days = params[:days].presence&.to_i
    CallSuppression.suppress!(domain: domain, reason: reason, days: days, by: param_agent)
    CallEvent.record!(domain: domain, type: "suppressed", agent: param_agent, payload: { reason: reason, days: days })
    redirect_back_to_day("Suppressed #{domain}")
  end

  def skip
    target = CallTarget.find(params[:id])
    target.update!(status: "skipped")
    CallEvent.record!(domain: target.shopify_domain, type: "skipped", agent: param_agent,
                      payload: { reason: params[:reason] })
    redirect_back_to_day("Skipped #{target.shopify_domain}")
  end

  def top_up
    date = parse_date(params[:date]) || Date.current
    before = CallTarget.for_date(date).count
    SupportCalls::QueueBuilder.new(date: date).top_up!
    added = CallTarget.for_date(date).count - before
    message = added.positive? ? "Added #{added} to the queue" : "Queue already full"
    redirect_to support_dashboard_call_calendar_path(date: params[:date].presence), notice: message
  rescue => e
    Rails.logger.error("[CallCalendar top_up] #{e.class}: #{e.message}")
    redirect_to support_dashboard_call_calendar_path(date: params[:date].presence), alert: "Refresh failed: #{e.message}"
  end

  # Append the next batch of targets beyond the daily cap, so the caller can
  # keep going once the day's 50 are worked through.
  def get_next
    date = parse_date(params[:date]) || Date.current
    count = params[:count].to_i
    count = 50 unless count.positive?
    before = CallTarget.for_date(date).count
    SupportCalls::QueueBuilder.new(date: date).add_more!(count)
    added = CallTarget.for_date(date).count - before
    message = added.positive? ? "Added #{added} more to the queue" : "No more candidates to add"
    redirect_to support_dashboard_call_calendar_path(date: params[:date].presence, tab: params[:tab].presence), notice: message
  rescue => e
    Rails.logger.error("[CallCalendar get_next] #{e.class}: #{e.message}")
    redirect_to support_dashboard_call_calendar_path(date: params[:date].presence), alert: "Couldn't add more: #{e.message}"
  end

  def build_now
    targets = SupportCalls::QueueBuilder.new(date: Date.current).build!(force: params[:force].present?)
    redirect_to support_dashboard_call_calendar_path, notice: "Queue built (#{targets.size} targets)"
  rescue => e
    Rails.logger.error("[CallCalendar build] #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}")
    redirect_to support_dashboard_call_calendar_path, alert: "Build failed: #{e.class}: #{e.message}"
  end

  private

  def authenticate_admin!
    http_basic_authenticate_or_request_with(
      name: ENV.fetch("ADMIN_USER", nil),
      password: ENV.fetch("ADMIN_PASS", nil)
    )
  end

  def apply_outcome_side_effects(domain, outcome, agent)
    config = CallRecord::SUPPRESS_OUTCOMES[outcome]
    return unless config

    CallSuppression.suppress!(domain: domain, reason: config[:reason], days: config[:days], by: agent)
    CallEvent.record!(domain: domain, type: "suppressed", agent: agent, payload: { reason: config[:reason], via: outcome })
  end

  def mark_target_attempted(id)
    return if id.blank?

    CallTarget.where(id: id).update_all(status: "attempted", updated_at: Time.current)
  end

  # Record that a call was attempted so the shop shows up in the Done list.
  # If it was a queued target we just flip its status; if the outcome was logged
  # for a shop that wasn't in today's queue (e.g. from search, or a callback),
  # create an attempted target for the day so it still lands in Done and counts.
  def record_attempt(domain, call_target_id, segment)
    if call_target_id.present?
      mark_target_attempted(call_target_id)
    elsif domain.present?
      date = parse_date(params[:date]) || Date.current
      target = CallTarget.find_or_initialize_by(call_date: date, shopify_domain: domain)
      target.segment = segment.presence || target.segment.presence || "active"
      target.status = "attempted"
      target.save!
    end
  end

  def build_rows(targets)
    domains = targets.map(&:shopify_domain)
    last_contact = CallRecord.where(shopify_domain: domains).group(:shopify_domain).maximum(:called_at)
    reminders = CallReminder.open_reminders.where(shopify_domain: domains).group_by(&:shopify_domain)
    events = CallEvent.where(shopify_domain: domains).order(occurred_at: :desc).group_by(&:shopify_domain)
    due_domains = CallReminder.open_domains_due_by(@date).to_set
    shops = shops_by_id_for(targets.map(&:shop_id))

    targets.map do |target|
      shop = shops[target.shop_id]
      {
        target: target,
        phone: target.contact_phone,
        crisp_url: target.crisp_url,
        admin_path: target.admin_path,
        display_domain: display_domain_for(target),
        store_url: store_url_for(display_domain_for(target)),
        last_contact: last_contact[target.shopify_domain],
        reminders: reminders[target.shopify_domain] || [],
        events: (events[target.shopify_domain] || []).first(8),
        due: due_domains.include?(target.shopify_domain),
        plan_label: plan_label_for(shop),
        plan_active: shop&.billing_activated? || false,
        features: features_for(shop)
      }
    end
  end

  # Batch-load shops (with their setting + plan) for a set of shop_ids, so the
  # plan/features panel adds no per-row queries.
  def shops_by_id_for(shop_ids)
    ids = shop_ids.compact.uniq
    return {} if ids.empty?

    Shop.where(id: ids).includes(:setting, :plan).index_by(&:id)
  end

  # Enabled feature toggles for a shop, as display labels, driven by
  # Setting::CHURN_ADOPTION_COLUMNS (the canonical adoption set).
  def features_for(shop)
    setting = shop&.setting
    return [] if setting.blank?

    Setting::CHURN_ADOPTION_COLUMNS.select { |col|
      setting.respond_to?(col) && ActiveModel::Type::Boolean.new.cast(setting.public_send(col))
    }.map { |col| FEATURE_LABELS[col] || col.tr("_", " ").capitalize }
  end

  def plan_label_for(shop)
    return nil if shop.nil?

    shop.plan&.name.presence || "Free"
  end

  # Rows for the "Scheduled callbacks" tab: one per open CallReminder, enriched
  # with the same context the main queue rows carry (shop, phone, timeline
  # events, last contact, open reminders) so the row can render the shared
  # detail panel with the full set of actions. All lookups are batch-loaded.
  def build_callback_rows(callbacks)
    domains = callbacks.map(&:shopify_domain).uniq
    shops = Shop.where(shopify_domain: domains).includes(:setting, :plan).index_by(&:shopify_domain)
    last_contact = CallRecord.where(shopify_domain: domains).group(:shopify_domain).maximum(:called_at)
    events = CallEvent.where(shopify_domain: domains).order(occurred_at: :desc).group_by(&:shopify_domain)
    open_reminders = CallReminder.open_reminders.where(shopify_domain: domains).group_by(&:shopify_domain)

    callbacks.map do |reminder|
      shop = shops[reminder.shopify_domain]
      display = shop&.primary_domain.presence || reminder.shopify_domain
      {
        reminder: reminder,
        display_domain: display,
        store_url: store_url_for(display),
        phone: shop&.owner_phone,
        shop_id: shop&.id,
        segment: shop ? "active" : nil,
        admin_path: shop ? "/admin/shops/#{shop.id}" : nil,
        crisp_url: crisp_for(shop, nil),
        last_contact: last_contact[reminder.shopify_domain],
        reminders: open_reminders[reminder.shopify_domain] || [],
        events: (events[reminder.shopify_domain] || []).first(8),
        overdue: reminder.due_on < @date,
        plan_label: plan_label_for(shop),
        plan_active: shop&.billing_activated? || false,
        features: features_for(shop)
      }
    end
  end

  # Rows for the "Demo scheduled" tab: one per CallDemo, with the scheduled time,
  # owner and status, plus the same context the other tabs carry (timeline
  # events, last contact, reminders, plan/features) so each row can expand into
  # the shared detail panel. All lookups are batch-loaded.
  def build_demo_rows(demos)
    domains = demos.map(&:shopify_domain).uniq
    shops = Shop.where(shopify_domain: domains).includes(:setting, :plan).index_by(&:shopify_domain)
    last_contact = CallRecord.where(shopify_domain: domains).group(:shopify_domain).maximum(:called_at)
    events = CallEvent.where(shopify_domain: domains).order(occurred_at: :desc).group_by(&:shopify_domain)
    open_reminders = CallReminder.open_reminders.where(shopify_domain: domains).group_by(&:shopify_domain)

    demos.map do |demo|
      shop = shops[demo.shopify_domain]
      display = shop&.primary_domain.presence || demo.shopify_domain
      {
        demo: demo,
        display_domain: display,
        store_url: store_url_for(display),
        phone: shop&.owner_phone,
        shop_id: shop&.id,
        segment: shop ? "active" : nil,
        admin_path: shop ? "/admin/shops/#{shop.id}" : nil,
        crisp_url: crisp_for(shop, nil),
        last_contact: last_contact[demo.shopify_domain],
        reminders: open_reminders[demo.shopify_domain] || [],
        events: (events[demo.shopify_domain] || []).first(8),
        plan_label: plan_label_for(shop),
        plan_active: shop&.billing_activated? || false,
        features: features_for(shop),
        demo_time: demo.scheduled_at,
        logged_at: demo.created_at,
        owner: demo.owner,
        status: demo.status,
        status_label: demo.status_label,
        notes: demo.notes
      }
    end
  end

  # Aggregate report over [from..to] for the Stats tab: callbacks scheduled per
  # team and their outcomes, plus demos by status and call outcomes.
  def compute_stats(from, to)
    range = from.beginning_of_day..to.end_of_day
    reminders = CallReminder.where(created_at: range)
    demos = CallDemo.where(created_at: range)
    records = CallRecord.where(called_at: range)

    callbacks = CallReminder::TEAMS.index_with do |team|
      team_scope = reminders.for_team(team)
      {
        scheduled: team_scope.count,
        done: team_scope.where(status: "done").count,
        open: team_scope.where(status: "open").count,
        outcomes: team_scope.where.not(outcome: nil).group(:outcome).count
      }
    end

    {
      from: from,
      to: to,
      callbacks: callbacks,
      callbacks_total: reminders.count,
      demo_status_counts: demos.group(:status).count,
      demos_total: demos.count,
      call_outcomes: records.group(:outcome).count,
      calls_total: records.count
    }
  end

  def display_domain_for(target)
    return target.shopify_domain if target.segment == "churned"

    target.shop&.primary_domain.presence || target.shopify_domain
  end

  def store_url_for(domain)
    "https://#{domain.to_s.sub(%r{\Ahttps?://}, '')}"
  end

  def build_search_row(query)
    raw = query.to_s.strip
    digits = raw.gsub(/\D/, "")

    shop = nil
    uninstalled = nil

    # Phone search: the query is phone-shaped (only digits/space/+/()/-) and has
    # enough digits to be a real number. Compare on digits only so formatting and
    # country-code differences don't matter.
    if digits.length >= 6 && raw.match?(/\A[\d\s()+\-]+\z/)
      shop = Shop.where("regexp_replace(coalesce(owner_phone, ''), '[^0-9]', '', 'g') LIKE ?", "%#{digits}%").first
      uninstalled = shop ? nil : UninstalledShop.where("regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g') LIKE ?", "%#{digits}%").order(created_at: :desc).first
    end

    # Domain search (default, and fallback when no phone match).
    unless shop || uninstalled
      domain = raw.downcase.sub(%r{\Ahttps?://}, "").sub(%r{/.*\z}, "").strip
      return { found: false, query: query } if domain.blank?

      shop = Shop.where("shopify_domain ILIKE :q OR primary_domain ILIKE :q", q: "%#{domain}%").first
      uninstalled = shop ? nil : UninstalledShop.where("shop_domain ILIKE ?", "%#{domain}%").order(created_at: :desc).first
    end

    return { found: false, query: query } unless shop || uninstalled

    resolved = shop&.shopify_domain || uninstalled&.shop_domain
    display = (shop&.primary_domain).presence || resolved

    {
      found: true,
      domain: resolved,
      display_domain: display,
      store_url: store_url_for(display),
      shop_id: shop&.id,
      segment: shop ? "active" : "churned",
      phone: shop&.owner_phone || uninstalled&.phone,
      crisp_url: crisp_for(shop, uninstalled),
      admin_path: shop ? "/admin/shops/#{shop.id}" : (uninstalled ? "/admin/uninstalled_shops/#{uninstalled.id}" : nil),
      last_contact: CallRecord.for_domain(resolved).maximum(:called_at),
      reminders: CallReminder.open_reminders.where(shopify_domain: resolved).to_a,
      events: CallEvent.for_domain(resolved).limit(15).to_a,
      plan_label: plan_label_for(shop),
      plan_active: shop&.billing_activated? || false,
      features: features_for(shop)
    }
  end

  def crisp_for(shop, uninstalled)
    return shop.crisp_url if shop.respond_to?(:crisp_url) && shop&.crisp_url.present?

    email = shop&.owner_email || uninstalled&.email
    website_id = ENV.fetch("CRISP_WEBSITE_ID", nil)
    return nil if website_id.blank? || email.blank?

    "https://go.crisp.chat/chat/embed/?website_id=#{website_id}&user_email=#{CGI.escape(email)}"
  end

  def param_domain
    params[:shopify_domain].to_s.strip
  end

  def param_agent
    params[:agent].to_s.strip.presence || SupportCalls::DayOwner.for_date(Date.current)
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  # A demo that has been given a new date is still an upcoming demo, so it stays
  # "scheduled" and keeps showing in the Scheduled list — "rescheduled" is never
  # a resting status. Re-dating a closed-out demo (no-show, cancelled) reopens
  # it, unless the agent picked a different closed status in the same submit.
  def resolved_demo_status(raw_status, rescheduled_at, current_status)
    status = CallDemo.normalize_status(raw_status)
    return "scheduled" if status == "rescheduled"
    return status if rescheduled_at.blank?
    return "scheduled" if status == current_status || CallDemo::OPEN_STATUSES.include?(status)

    status
  end

  # Parse a datetime-local string ("2026-08-10T15:30") or a stored ISO8601 value
  # in the app timezone. Returns a Time, or nil on blank/invalid input.
  def parse_demo_at(value)
    return nil if value.blank?

    (Time.zone || Time).parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def redirect_back_to_day(message)
    redirect_to support_dashboard_call_calendar_path(date: params[:date].presence, q: params[:q].presence,
                                                     tab: params[:tab].presence, cb_team: params[:cb_team].presence), notice: message
  end

  def redirect_to_demos(message)
    redirect_to support_dashboard_call_calendar_path(tab: "demos", demo_status: params[:demo_status].presence), notice: message
  end
end
