module Api
  module Whatsapp
    class CampaignsController < AuthenticatedController
      QUALITY_LOW_ERROR = 'Your number quality is low. Sending now could get your number restricted.'

      before_action :load_campaign, only: %i[show update destroy launch pause resume cancel retry_now test report recipients preview]

      def index
        campaigns = WhatsappCampaign.where(shop_id: @shop.id).includes(:whatsapp_account).order(created_at: :desc).limit(200)
        render json: { campaigns: campaigns.map { |c| serialize(c) }, schedule_timezone: schedule_timezone_info }
      end

      # Everything the campaigns page needs to decide what to show first: the
      # setup checklist (number, approved template, contacts) when something is
      # missing, and the headline numbers once campaigns have gone out.
      def overview
        account = @shop.default_whatsapp_account
        # Campaigns can only broadcast marketing and utility templates.
        campaign_templates = @shop.whatsapp_templates.where(category: %i[marketing utility])
        contacts = WhatsappContact.where(shop_id: @shop.id)
        recent = WhatsappCampaign.where(shop_id: @shop.id).where('started_at >= ?', 30.days.ago)
        sent, delivered, read, failed, replied =
          recent.pick(*%w[sent_count delivered_count read_count failed_count replied_count]
                        .map { |col| Arel.sql("COALESCE(SUM(#{col}), 0)") }).map(&:to_i)

        render json: {
          account: account ? {
            connected: true, ready_to_send: account.ready_to_send?, status: account.status,
            display_phone_number: account.display_phone_number, verified_name: account.verified_name,
            needs_registration: account.needs_registration?
          } : { connected: false, ready_to_send: false },
          templates: {
            approved: campaign_templates.approved.count,
            pending: campaign_templates.pending.count
          },
          contacts: {
            total: contacts.count,
            subscribed: contacts.subscribed.count,
            sync: ::Whatsapp::SyncContactsJob.status(@shop.id)
          },
          audiences_count: WhatsappSegment.where(shop_id: @shop.id).count,
          campaigns_count: WhatsappCampaign.where(shop_id: @shop.id).count,
          last_30_days: {
            campaigns: recent.count,
            # Recipient counts are per current status, so a read message is no
            # longer in delivered_count and a delivered one no longer in sent_count.
            sent: sent + delivered + read,
            delivered: delivered + read,
            read: read,
            failed: failed,
            replied: replied
          },
          schedule_timezone: schedule_timezone_info
        }
      end

      def show
        render json: { campaign: serialize(@campaign, full: true), schedule_timezone: schedule_timezone_info }
      end

      def create
        return if invalid_scheduled_at_param?
        campaign = WhatsappCampaign.new(campaign_params.merge(shop_id: @shop.id, status: 'draft'))
        if campaign.save
          render json: { campaign: serialize(campaign) }, status: :created
        else
          render json: { error: campaign.errors.full_messages.to_sentence }, status: :unprocessable_entity
        end
      end

      def update
        return draft_only unless @campaign.status == 'draft'
        return if invalid_scheduled_at_param?
        if @campaign.update(campaign_params)
          render json: { campaign: serialize(@campaign) }
        else
          render json: { error: @campaign.errors.full_messages.to_sentence }, status: :unprocessable_entity
        end
      end

      def destroy
        return draft_only unless %w[draft completed cancelled failed].include?(@campaign.status)
        @campaign.destroy
        head :no_content
      end

      def launch
        # Send from the chosen number (multi-number) or the campaign's template's
        # own account, falling back to the shop default. The sending number must
        # share the template's WABA or Meta rejects the send.
        template = @campaign.whatsapp_template
        account =
          if params[:whatsapp_account_id].present?
            @shop.whatsapp_accounts.find_by(id: params[:whatsapp_account_id])
          else
            @campaign.whatsapp_account || template&.whatsapp_account || @shop.default_whatsapp_account
          end
        return render_error("WhatsApp account isn't verified yet.") unless account&.ready_to_send?
        return render_error('Bound template is not approved by WhatsApp.') unless template&.approved?
        if template.whatsapp_account&.waba_id.present? && account.waba_id.to_s != template.whatsapp_account.waba_id.to_s
          return render_error('Selected number is under a different WhatsApp Business Account than the template.')
        end
        @campaign.whatsapp_account = account
        return render_error('Campaign is not in a launchable state.') unless @campaign.launchable?
        if @campaign.audience_source == 'segment' && @campaign.whatsapp_segment.nil?
          return render_error('Pick a segment for this campaign (it may have been deleted).')
        end
        return render_error(QUALITY_LOW_ERROR, code: 'quality_low') if account.quality_low? && !risk_acknowledged?

        columns = { whatsapp_account_id: account.id, status: 'building', completed_at: nil, last_error: nil, updated_at: Time.current,
                    pause_reason: nil, paused_at: nil, guardrail_notified_at: nil,
                    pause_detail: account.quality_low? ? ::Whatsapp::CampaignGuardrails.acknowledgement_for(account) : {} }
        columns[:scheduled_at] = nil if params[:send_now]
        if params[:scheduled_at].present?
          at = parse_in_shop_tz(params[:scheduled_at])
          return render_error("Scheduled time is invalid or in the past (times are read in #{schedule_timezone_label}).") if at.nil? || at <= Time.current
          columns[:scheduled_at] = at
        elsif !params[:send_now] && @campaign.scheduled_at.present? && @campaign.scheduled_at <= Time.current
          # A draft/cancelled campaign carrying a stale scheduled_at would
          # otherwise be treated as due-now by BuildAudienceJob and go out
          # immediately — surprising when the merchant thought they scheduled it.
          return render_error(
            "The saved send time (#{format_in_shop_tz(@campaign.scheduled_at)}) has already passed. " \
            'Pick a new time or choose Send now.'
          )
        end
        @campaign.update_columns(columns)
        ::Whatsapp::BuildAudienceJob.perform_async(@campaign.id)
        render json: { campaign: serialize(@campaign), message: 'Building audience and starting send.' }
      end

      def pause
        return render_error('Only a sending campaign can be paused.') unless @campaign.status == 'sending'
        now = Time.current
        @campaign.update_columns(status: 'paused', pause_reason: nil, paused_at: now, updated_at: now)
        render json: { campaign: serialize(@campaign) }
      end

      def resume
        return render_error('Only a paused campaign can be resumed.') unless @campaign.status == 'paused'
        account = @campaign.whatsapp_account
        low = account&.quality_low?
        return render_error(QUALITY_LOW_ERROR, code: 'quality_low') if low && !risk_acknowledged?

        now = Time.current
        detail = { 'resumed_at' => now.iso8601 }
        detail.merge!(::Whatsapp::CampaignGuardrails.acknowledgement_for(account, now)) if low
        # Auto-pause also catches campaigns that were only scheduled; resuming one
        # must keep the merchant's send time rather than start sending now.
        if @campaign.started_at.nil? && @campaign.scheduled_at.present? && @campaign.scheduled_at > now
          @campaign.update_columns(status: 'scheduled', pause_reason: nil, paused_at: nil, guardrail_notified_at: nil,
                                   pause_detail: detail, updated_at: now)
          return render json: { campaign: serialize(@campaign) }
        end
        unless WhatsappCampaign.sending_slots_available.positive?
          return render_error("Too many campaigns are sending right now (limit #{WhatsappCampaign.max_concurrent}). Pause or wait for one to finish, then resume.")
        end
        @campaign.update_columns(status: 'sending', pause_reason: nil, paused_at: nil, guardrail_notified_at: nil,
                                 pause_detail: detail, updated_at: now)
        ::Whatsapp::CampaignDispatchJob.perform_async(@campaign.id)
        render json: { campaign: serialize(@campaign) }
      end

      def retry_now
        return render_error('No retries are waiting for this campaign.') unless @campaign.status == 'retry_waiting'
        unless WhatsappCampaign.sending_slots_available.positive?
          return render_error("Too many campaigns are sending right now (limit #{WhatsappCampaign.max_concurrent}). Try again once one finishes.")
        end
        @campaign.recipients.awaiting_retry.update_all(next_retry_at: Time.current, updated_at: Time.current)
        @campaign.update_columns(status: 'sending', updated_at: Time.current)
        ::Whatsapp::CampaignDispatchJob.perform_async(@campaign.id)
        render json: { campaign: serialize(@campaign) }
      end

      def cancel
        return render_error('Campaign already finished.') if @campaign.terminal?
        @campaign.update_columns(status: 'cancelled', completed_at: Time.current, updated_at: Time.current)
        render json: { campaign: serialize(@campaign) }
      end

      def test
        phones = Array(params[:phones]).map { |p| p.to_s.gsub(/\D/, '') }.reject(&:blank?).first(10)
        return render_error('Provide at least one test phone number.') if phones.empty?
        template = @campaign.whatsapp_template
        # Test from the campaign's chosen number (or its template's account),
        # falling back to the shop default.
        account = @campaign.whatsapp_account || template&.whatsapp_account || @shop.default_whatsapp_account
        return render_error("Account not ready or template not approved.") unless account&.ready_to_send? && template&.approved?

        sample = sample_recipient_data
        fields = sample&.dig(:fields) || placeholder_fields

        sent = phones.map do |phone|
          rcpt = WhatsappCampaignRecipient.new(whatsapp_campaign: @campaign, shop_id: @shop.id, phone: phone, name: sample&.dig(:name), fields: fields)
          missing = ::Whatsapp::CampaignMessageBuilder.missing_values(@campaign, rcpt)
          if missing.any?
            next { phone: phone, status: 'skipped',
                   error: "Recipient would be skipped — missing: #{missing.join(', ')}. Map the field or set a default value." }
          end

          log = ::Meta::SendTemplateMessageService.call(
            account: account, template: template, recipient: phone,
            body_parameters: ::Whatsapp::CampaignMessageBuilder.body_parameters(@campaign, rcpt),
            header_parameters: ::Whatsapp::CampaignMessageBuilder.header_parameters(@campaign, template, rcpt),
            event_type_key: 'campaign_test',
            payload_snapshot: { 'campaign_id' => @campaign.id, 'test' => true },
            button_slug: ::Whatsapp::CampaignMessageBuilder.button_slug(@campaign, rcpt),
            source_external_id: "wactest:#{@campaign.id}:#{phone}:#{Time.now.to_i}"
          )
          { phone: phone, status: log&.status, error: log&.error_message,
            button_url: ::Whatsapp::CampaignMessageBuilder.button_url(@campaign, rcpt) }
        rescue ::Meta::SendTemplateMessageService::Error => e
          { phone: phone, status: 'failed', error: e.message }
        end

        render json: { results: sent }
      end

      def report
        failures = WhatsappMessageLog.where(whatsapp_campaign_id: @campaign.id, status: 4)
                                     .group(:error_code).count
        render json: {
          campaign: serialize(@campaign, full: true),
          deliverability: @campaign.deliverability,
          progress_pct: @campaign.progress_pct,
          failure_breakdown: failures
        }
      end

      def recipients
        scope = @campaign.recipients
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where('phone ILIKE :q OR name ILIKE :q', q: "%#{params[:q]}%") if params[:q].present?
        page = scope.order(updated_at: :desc).limit(100).offset(params[:offset].to_i)
        render json: { recipients: page.map { |r| recipient_json(r) }, total: scope.count }
      end

      def preview
        sample = sample_recipient_data
        fields = sample&.dig(:fields) || placeholder_fields
        rcpt = WhatsappCampaignRecipient.new(fields: fields, name: sample&.dig(:name), phone: sample&.dig(:phone))
        render json: {
          body_parameters: ::Whatsapp::CampaignMessageBuilder.body_parameters(@campaign, rcpt),
          missing: ::Whatsapp::CampaignMessageBuilder.missing_values(@campaign, rcpt)
        }
      end

      private

      def load_campaign
        @campaign = WhatsappCampaign.find_by(id: params[:id], shop_id: @shop.id)
        render(json: { error: 'Campaign not found' }, status: :not_found) unless @campaign
      end

      # Draft campaigns have no snapshot recipients yet, so pull one live row
      # from the audience source to give tests/previews realistic values.
      def sample_recipient_data
        existing = @campaign.recipients.where.not(status: 'suppressed').first
        return { fields: existing.fields, name: existing.name, phone: existing.phone } if existing

        found = nil
        ::Whatsapp::AudienceBuilder.each_recipient(@campaign, limit: 1) do |r|
          found = { fields: r[:fields], name: r[:name], phone: r[:phone] }
          break
        end
        found
      rescue StandardError
        nil
      end

      def placeholder_fields
        @campaign.variable_mapping.values.index_with { |k| k.to_s.split('.').last.tr('_', ' ') }
      end

      def campaign_params
        permitted = params.permit(:name, :description, :audience_source, :whatsapp_template_id, :whatsapp_account_id,
                                  :whatsapp_audience_import_id, :whatsapp_segment_id, :button_field, :header_field,
                                  :rate_per_minute, :scheduled_at, :missing_value_policy,
                                  audience_filter: {}, variable_mapping: {}, variable_defaults: {}, discount_config: {},
                                  retry_config: [:enabled, { delays_hours: [] }],
                                  send_policy: { quiet_hours: %i[enabled start_hour end_hour], frequency_cap: %i[enabled hours] })
        permitted[:scheduled_at] = parse_in_shop_tz(permitted[:scheduled_at]) if permitted[:scheduled_at].present?
        permitted[:retry_config] = ::Whatsapp::CampaignRetryPolicy.sanitize_config(permitted[:retry_config]) if params.key?(:retry_config)
        permitted[:send_policy] = ::Whatsapp::SendPolicy.sanitize(permitted[:send_policy]) if params.key?(:send_policy)
        if permitted[:whatsapp_account_id].present? &&
           !@shop.whatsapp_accounts.exists?(id: permitted[:whatsapp_account_id])
          permitted[:whatsapp_account_id] = nil
        end
        if permitted[:whatsapp_segment_id].present? &&
           !WhatsappSegment.exists?(id: permitted[:whatsapp_segment_id], shop_id: @shop.id)
          permitted[:whatsapp_segment_id] = nil
        end
        permitted
      end

      # datetime-local strings from the wizard carry no zone and merchants think
      # in store time, so parsing (write) and display (read) must use this same
      # zone or the shown time won't match what was entered.
      def shop_tz
        resolve_shop_tz.first
      end

      def shop_tz_managed?
        resolve_shop_tz.last
      end

      def resolve_shop_tz
        @resolve_shop_tz ||= ::Whatsapp::ShopTimezone.resolve(@shop)
      end

      # "Asia/Kolkata (UTC+05:30)" / "UTC" — used in help text and errors.
      def schedule_timezone_label
        tz = shop_tz
        tz.name == 'UTC' ? 'UTC' : "#{tz.name} (UTC#{tz.formatted_offset})"
      end

      def schedule_timezone_info
        tz = shop_tz
        {
          name: tz.name,
          utc_offset: tz.formatted_offset,
          label: schedule_timezone_label,
          managed: shop_tz_managed?,
          now: Time.current.in_time_zone(tz).strftime('%Y-%m-%dT%H:%M'),
          now_display: format_in_shop_tz(Time.current)
        }
      end

      # Rejects (and renders) an unparseable scheduled_at instead of letting
      # campaign_params silently coerce it to nil — which would drop the
      # schedule and make "Launch" send immediately. Returns true when rendered.
      def invalid_scheduled_at_param?
        return false unless params[:scheduled_at].present?
        return false if parse_in_shop_tz(params[:scheduled_at])
        render_error("Scheduled time is invalid (expected a date and time, read in #{schedule_timezone_label}).")
        true
      end

      def parse_in_shop_tz(value)
        str = value.to_s.strip
        return nil if str.blank?
        # datetime-local from the wizard ("2026-09-16T10:30") carries no offset
        # → wall-clock in the store zone. An explicit offset/Z (API callers) is
        # honoured as-is by TimeZone#parse.
        shop_tz.parse(str)
      rescue ArgumentError, TypeError
        nil
      end

      # Preformatted for the list — rendered in the store's zone (with the zone
      # label) so it reads back exactly as scheduled, independent of the
      # viewer's browser timezone.
      def format_in_shop_tz(time)
        return nil unless time
        time.in_time_zone(shop_tz).strftime('%d/%m/%Y, %I:%M %p %Z')
      end

      def draft_only
        render json: { error: 'Only draft campaigns can be edited.' }, status: :unprocessable_entity
      end

      def render_error(msg, code: nil)
        body = { error: msg }
        body[:code] = code if code
        render json: body, status: :unprocessable_entity
      end

      def risk_acknowledged?
        ActiveModel::Type::Boolean.new.cast(params[:acknowledge_risk]) == true
      end

      def quality_account_for(campaign)
        campaign.whatsapp_account || (@default_quality_account ||= [@shop.default_whatsapp_account]).first
      end

      def serialize(c, full: false)
        base = {
          id: c.id, name: c.name, description: c.description, status: c.status,
          audience_source: c.audience_source, template_id: c.whatsapp_template_id,
          scheduled_at: c.scheduled_at, scheduled_at_display: format_in_shop_tz(c.scheduled_at),
          started_at: c.started_at, completed_at: c.completed_at,
          audience_count: c.audience_count, suppressed_count: c.suppressed_count,
          sent_count: c.sent_count, delivered_count: c.delivered_count, read_count: c.read_count,
          failed_count: c.failed_count, replied_count: c.replied_count,
          estimated_cost: c.estimated_cost, progress_pct: c.progress_pct,
          recipe_key: (c.respond_to?(:recipe_key) ? c.recipe_key : nil),
          last_error: c.last_error, retry_config: c.retry_config || {},
          pause_reason: c.pause_reason, pause_detail: c.pause_detail || {},
          paused_at: c.paused_at, paused_at_display: format_in_shop_tz(c.paused_at),
          send_policy: ::Whatsapp::SendPolicy.effective(c),
          quiet_hours: ::Whatsapp::SendPolicy.quiet_hours_label(c),
          account_quality_rating: quality_account_for(c)&.quality_rating
        }
        if full
          # datetime-local value (store tz) so the edit form prefills the same
          # wall-clock the merchant originally picked, not the UTC equivalent.
          base[:scheduled_at_input] = c.scheduled_at ? c.scheduled_at.in_time_zone(shop_tz).strftime('%Y-%m-%dT%H:%M') : nil
          base.merge!(audience_filter: c.audience_filter, variable_mapping: c.variable_mapping,
                      variable_defaults: c.variable_defaults, missing_value_policy: c.missing_value_policy,
                      button_field: c.button_field, header_field: c.header_field,
                      whatsapp_audience_import_id: c.whatsapp_audience_import_id,
                      whatsapp_segment_id: c.whatsapp_segment_id,
                      whatsapp_account_id: c.whatsapp_account_id,
                      rate_per_minute: c.rate_per_minute, deliverability: c.deliverability,
                      retry_pending_count: c.retry_pending_count,
                      next_retry_at: c.next_retry_at,
                      next_retry_at_display: format_in_shop_tz(c.next_retry_at))
        end
        base
      end

      def recipient_json(r)
        { id: r.id, phone: r.phone, name: r.name, status: r.status,
          suppression_reason: r.suppression_reason, error_code: r.error_code,
          error_message: r.error_message, sent_at: r.sent_at, delivered_at: r.delivered_at,
          read_at: r.read_at, failed_at: r.failed_at,
          attempt_count: r.attempt_count, next_retry_at: r.next_retry_at }
      end
    end
  end
end
